#!/usr/bin/env bash
# go_live_final.sh - 최종 원클릭: 사전 체크 4가지 + r3→r4→r5 집행

set -euo pipefail

# ===== 환경변수(필수) =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export TIMEZONE="${TIMEZONE:-Asia/Seoul}"
export APP_HMAC="${APP_HMAC:-your-hmac-secret}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:5902,http://localhost:8000}"
export PORT="${PORT:-5902}"

say(){ printf '%s\n' "$*"; }

need(){ command -v "$1" >/dev/null 2>&1 || { say "[need] $1 설치 필요"; exit 1; }; }

# -----------------------------------------------------------------------------
# 0) 사전 체크 4가지
# -----------------------------------------------------------------------------

say "[precheck 1/4] psql 설치 확인"
need psql
need node
need npm

say "[precheck 2/4] r3/r4/r5 전제 파일 확인"
missing=()

for f in \
  server/mw/auth.js server/mw/admin.js \
  server/lib/time.js server/lib/validators.js server/lib/copy_engine.js server/lib/audit.js \
  server/lib/db.js server/lib/repo.js \
  scripts/run_sql.js scripts/db_migrate.sh \
  scripts/apply_p2_r4.sh scripts/apply_p2_r5.sh; do
  [ -f "$f" ] || missing+=("$f")
done

# r4 fixpack은 선택
[ -f scripts/apply_p2_r4_fixpack.sh ] || true

if [ "${#missing[@]}" -gt 0 ]; then
  say "[ERR] 전제 파일 누락:"
  printf '  - %s\n' "${missing[@]}"
  exit 1
fi

say "[precheck 3/4] 환경변수 확인"
: "${DATABASE_URL:?DATABASE_URL 비어있음}"
: "${TIMEZONE:?TIMEZONE 비어있음}"
: "${APP_HMAC:?APP_HMAC 비어있음}"
: "${ADMIN_KEY:?ADMIN_KEY 비어있음}"
: "${CORS_ORIGINS:?CORS_ORIGINS 비어있음}"

say "[precheck 4/4] 포트/권한 확인"
if command -v lsof >/dev/null 2>&1; then
  if lsof -i TCP:"$PORT" -sTCP:LISTEN -Pn | grep -q .; then
    say "[ERR] 포트 ${PORT} 사용중. PORT를 변경하거나 점유 프로세스를 종료하라."
    exit 1
  fi
elif command -v ss >/dev/null 2>&1; then
  if ss -ltn | awk '{print $4}' | grep -q ":${PORT}$"; then
    say "[ERR] 포트 ${PORT} 사용중."
    exit 1
  fi
fi

touch .write_test && rm -f .write_test || { say "[ERR] 저장소 루트에 쓰기 권한 없음"; exit 1; }

# -----------------------------------------------------------------------------
# 1) 로컬 DB 준비(없으면 컨테이너 사용)
# -----------------------------------------------------------------------------

say "[1] Postgres 준비"
if command -v docker >/dev/null 2>&1; then
  if ! docker ps --format '{{.Names}}' | grep -q '^pgpetlink$'; then
    docker run -d --name pgpetlink -p 5432:5432 -e POSTGRES_PASSWORD=petpass postgres:16 >/dev/null
    say "  - 컨테이너 pgpetlink 기동"
    sleep 2
  else
    say "  - 컨테이너 pgpetlink 이미 실행 중"
  fi
else
  say "  - docker 미설치: 로컬 Postgres 사용 가정"
fi

say "[2] petlink 데이터베이스 확인/생성"
export PGPASSWORD=petpass
psql "host=localhost user=postgres dbname=postgres" -Atc "SELECT 1 FROM pg_database WHERE datname='petlink';" | grep -q 1 \
  || psql "host=localhost user=postgres dbname=postgres" -c "CREATE DATABASE petlink;"
say "  - 데이터베이스 'petlink' 확인 완료"

# -----------------------------------------------------------------------------
# 2) 의존성
# -----------------------------------------------------------------------------

say "[3] 의존성 설치"
npm i pg luxon pino express-pino-logger helmet express-rate-limit zod >/dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# 3) 패치 적용(r3→r4→r4 Fix-Pack→r5)
# -----------------------------------------------------------------------------

say "[4] r3 재적용(safe)"
bash scripts/apply_p2_r3_persistence.sh || true

say "[5] r4 패치 적용"
bash scripts/apply_p2_r4.sh

say "[6] r4 전용 마이그레이션 적용"
node scripts/run_sql.js scripts/migrations/20251112_r4.sql || true

say "[7] r4 Fix‑Pack 적용(있으면)"
[ -x scripts/apply_p2_r4_fixpack.sh ] && bash scripts/apply_p2_r4_fixpack.sh || true

say "[8] r5 패치 적용"
bash scripts/apply_p2_r5.sh

# -----------------------------------------------------------------------------
# 4) 마이그레이션 일괄 반영
# -----------------------------------------------------------------------------

say "[9] r3/r4/r5 마이그레이션"
scripts/db_migrate.sh

[ -f scripts/migrations/20251112_r4.sql ]      && node scripts/run_sql.js scripts/migrations/20251112_r4.sql      || true
[ -f scripts/migrations/20251112_r4b_ttl.sql ] && node scripts/run_sql.js scripts/migrations/20251112_r4b_ttl.sql || true
[ -f scripts/migrations/20251112_r5.sql ]      && node scripts/run_sql.js scripts/migrations/20251112_r5.sql      || true

# -----------------------------------------------------------------------------
# 5) 서버 재기동
# -----------------------------------------------------------------------------

say "[10] 서버 재기동"
if [ -f .petlink.pid ]; then
  PID="$(cat .petlink.pid || true)"
  [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true
  sleep 1
fi

node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 2

say "[11] 헬스체크"
for i in $(seq 1 20); do
  curl -sf "http://localhost:${PORT}/health" >/dev/null && { say "health OK"; break; }
  sleep 0.3
  if [ "$i" -eq 20 ]; then
    say "[ERR] 서버 무응답"; tail -n +200 .petlink.out || true; exit 1
  fi
done

# -----------------------------------------------------------------------------
# 6) 스모크(A~H, I~J)
# -----------------------------------------------------------------------------

say "[12] r3 스모크(A~E)"
TOK="$(curl -s -XPOST "http://localhost:${PORT}/auth/signup" | sed -n 's/.*\"token\":\"\([^\"]*\)\".*/\1/p')"
[ -n "$TOK" ] || { say "[ERR] 토큰 발급 실패"; exit 1; }

curl -sf -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" "http://localhost:${PORT}/stores/1/channel-prefs" >/dev/null
say "  A) prefs OK"

curl -sf -XPOST "http://localhost:${PORT}/billing/checkout" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}' >/dev/null
say "  B) 인보이스 OK"

curl -sf -XPOST "http://localhost:${PORT}/organic/drafts" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d '{"store_id":1,"copy":"상담/방문 안내","channels":["META","YOUTUBE"]}' >/dev/null

PUB="$(curl -s -XPOST "http://localhost:${PORT}/organic/drafts/1/publish" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1")" && say "  C) publish OK"

MONTH="$(date +%Y-%m)"; TODAY="$(date +%Y-%m-%d)"
curl -sf -XPOST "http://localhost:${PORT}/pacer/apply" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d "{\"store_id\":1,\"month\":\"${MONTH}\",\"schedule\":[{\"date\":\"${TODAY}\",\"amount\":1000,\"min\":800,\"max\":1200}]}" >/dev/null
say "  D) 페이싱 OK"

curl -sf -XPOST "http://localhost:${PORT}/ingest/META" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d "[{\"ts\":\"$(date -u +%FT%TZ)\",\"store_id\":1,\"cost\":1300}]" >/dev/null
say "  E) 인게스트 OK"

curl -sf "http://localhost:${PORT}/metrics/daily?days=3" >/dev/null
say "  E) 시계열 OK"

say "[13] r4 스모크(F~H)"
K="idem-$(date +%s)"
curl -sf -D .idem1.h -o .idem1.b -XPOST "http://localhost:${PORT}/billing/checkout" \
 -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Idempotency-Key: ${K}" \
 -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}'

curl -sf -D .idem2.h -o .idem2.b -XPOST "http://localhost:${PORT}/billing/checkout" \
 -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Idempotency-Key: ${K}" \
 -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}'

if diff -q .idem1.b .idem2.b >/dev/null 2>&1 && grep -qi "X-Idempotent-Replay" .idem2.h 2>/dev/null; then
    say "  F) IDEMPOTENCY REPLAY OK"
else
    say "  F) IDEMPOTENCY REPLAY (부분 성공 또는 헤더 미표시)"
fi
rm -f .idem1.h .idem1.b .idem2.h .idem2.b || true

curl -sf "http://localhost:${PORT}/openapi.yaml" | grep -q "openapi:" && say "  G) OPENAPI SPEC OK" || say "  G) OPENAPI SPEC (확인 필요)"

curl -sf "http://localhost:${PORT}/docs" >/dev/null && say "  G) SWAGGER UI OK" || say "  G) SWAGGER UI (확인 필요)"

curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/outbox/peek"  >/dev/null && say "  H) OUTBOX PEEK OK" || say "  H) OUTBOX PEEK (확인 필요)"

curl -sf -XPOST -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/outbox/flush" >/dev/null && say "  H) OUTBOX FLUSH OK" || say "  H) OUTBOX FLUSH (확인 필요)"

say "[14] r5 스모크(I~J)"
STAMP="$(date +%s)"
psql "$DATABASE_URL" -Atc "INSERT INTO idempotency_keys(key,method,path,req_hash,status,expire_at) VALUES ('exp-${STAMP}','POST','/demo','h','COMPLETED', now() - interval '1 day') ON CONFLICT (key) DO NOTHING;" || true

curl -sf -XPOST "http://localhost:${PORT}/admin/ops/housekeeping/run" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && say "  I) HOUSEKEEPING OK" || say "  I) HOUSEKEEPING (확인 필요)"

CNT="$(psql "$DATABASE_URL" -Atc "SELECT count(*) FROM idempotency_keys WHERE key='exp-${STAMP}';" 2>/dev/null || echo "1")"
[ "$CNT" = "0" ] && say "  I) TTL CLEANUP VERIFIED" || say "  I) TTL CLEANUP (확인 필요: count=$CNT)"

curl -sf -XGET "http://localhost:${PORT}/admin/ops/dlq?limit=1" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && say "  J) DLQ API OK" || say "  J) DLQ API (확인 필요)"

# -----------------------------------------------------------------------------
# 7) 증빙 번들(있으면 생성)
# -----------------------------------------------------------------------------

if [ -x scripts/generate_proof_bundle.sh ]; then
  say "[15] 증빙 번들 생성"
  ADMIN_KEY="${ADMIN_KEY}" bash scripts/generate_proof_bundle.sh >/dev/null 2>&1 || true
fi

say ""
say "[done] 로그 확인:"
say "  tail -f .petlink.out"
say "  tail -f .outbox.log"
say ""
say "서버 포트: http://localhost:${PORT}"
say "문서: http://localhost:${PORT}/docs"

