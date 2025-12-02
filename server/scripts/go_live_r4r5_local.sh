#!/usr/bin/env bash
# go_live_r4r5_local.sh - r3→r4→r5 통합 로컬 실행 스크립트

set -euo pipefail

# ===== 환경변수 =====
export DATABASE_URL="postgres://postgres:petpass@localhost:5432/petlink"
export TIMEZONE="Asia/Seoul"
export APP_HMAC="your-hmac-secret"
export ADMIN_KEY="admin-dev-key-123"
export CORS_ORIGINS="http://localhost:5902,http://localhost:8000"
export PORT=5902

echo "[0] 사전 점검"
command -v node >/dev/null || { echo "[need] node가 없습니다. 설치 후 재시도하세요."; exit 1; }
command -v npm  >/dev/null || { echo "[need] npm이 없습니다. 설치 후 재시도하세요.";  exit 1; }
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }

# psql은 선택 (있으면 사용, 없으면 run_sql.js로 대체)
if command -v psql >/dev/null 2>&1; then
    USE_PSQL=true
    echo "  - psql 사용 가능"
else
    USE_PSQL=false
    echo "  - psql 없음, node scripts/run_sql.js로 대체"
fi

echo "[1] Postgres 컨테이너 없으면 기동"
if command -v docker >/dev/null 2>&1; then
  if ! docker ps --format '{{.Names}}' | grep -q '^pgpetlink$'; then
    docker run -d --name pgpetlink -p 5432:5432 -e POSTGRES_PASSWORD=petpass postgres:16 >/dev/null
    echo "  - postgres 컨테이너(pgpetlink) 기동"
    sleep 2
  else
    echo "  - postgres 컨테이너(pgpetlink) 이미 실행 중"
  fi
else
  echo "  - docker 미설치: 컨테이너 자동 기동은 건너뜁니다(로컬 Postgres 사용)."
fi

echo "[2] 데이터베이스 존재 확인/생성"
if [ "$USE_PSQL" = true ]; then
    export PGPASSWORD=petpass
    psql "host=localhost user=postgres dbname=postgres" -Atc "SELECT 1 FROM pg_database WHERE datname='petlink';" | grep -q 1 \
      || psql "host=localhost user=postgres dbname=postgres" -c "CREATE DATABASE petlink;"
    echo "  - 데이터베이스 'petlink' 확인 완료"
else
    # docker exec로 데이터베이스 생성 시도
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q '^pgpetlink$'; then
        echo "  - docker exec로 데이터베이스 생성 시도"
        docker exec pgpetlink psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='petlink';" | grep -q 1 \
          || docker exec pgpetlink psql -U postgres -c "CREATE DATABASE petlink;"
        echo "  - 데이터베이스 'petlink' 확인 완료"
    else
        echo "  - psql/docker 없음, 데이터베이스는 수동으로 생성 필요"
        echo "  - [WARN] 데이터베이스 'petlink'가 없으면 마이그레이션 실패 가능"
        echo "  - 수동 생성: docker exec pgpetlink psql -U postgres -c 'CREATE DATABASE petlink;'"
    fi
fi

echo "[3] 의존성(누락 방지)"
npm i pg luxon pino express-pino-logger helmet express-rate-limit zod >/dev/null 2>&1 || true

echo "[4] r3 재적용(safe)"
test -x scripts/apply_p2_r3_persistence.sh && bash scripts/apply_p2_r3_persistence.sh || true

echo "[5] r4 패치 적용"
test -x scripts/apply_p2_r4.sh || { echo "[ERR] scripts/apply_p2_r4.sh 없음"; exit 1; }
bash scripts/apply_p2_r4.sh

echo "[6] r4 마이그레이션 실행(중요)"
test -f scripts/migrations/20251112_r4.sql && node scripts/run_sql.js scripts/migrations/20251112_r4.sql || true

# r4 fixpack 스크립트가 있을 때만 수행
test -x scripts/apply_p2_r4_fixpack.sh && bash scripts/apply_p2_r4_fixpack.sh || true

echo "[7] r5 패치 적용"
if test -x scripts/apply_p2_r5.sh; then
    bash scripts/apply_p2_r5.sh
else
    echo "  - r5 패치 없음 (건너뜀)"
fi

echo "[8] r3/r4/r5 마이그레이션"
# 초기 마이그레이션 (r3) - 반드시 먼저 실행
echo "  - 초기 마이그레이션 실행"
if [ "$USE_PSQL" = true ] && test -x scripts/db_migrate.sh; then
    scripts/db_migrate.sh || {
        echo "  - db_migrate.sh 실패, run_sql.js로 대체"
        if test -f db/migrations/001_init.sql; then
            node scripts/run_sql.js db/migrations/001_init.sql || echo "  - [WARN] 초기 마이그레이션 실패"
        elif test -f scripts/migrations/001_init.sql; then
            node scripts/run_sql.js scripts/migrations/001_init.sql || echo "  - [WARN] 초기 마이그레이션 실패"
        fi
    }
else
    if test -f db/migrations/001_init.sql; then
        echo "  - db/migrations/001_init.sql 실행"
        node scripts/run_sql.js db/migrations/001_init.sql || echo "  - [WARN] 초기 마이그레이션 실패"
    elif test -f scripts/migrations/001_init.sql; then
        echo "  - scripts/migrations/001_init.sql 실행"
        node scripts/run_sql.js scripts/migrations/001_init.sql || echo "  - [WARN] 초기 마이그레이션 실패"
    else
        echo "  - [WARN] 초기 마이그레이션 파일 없음"
    fi
fi

# r4 마이그레이션
test -f scripts/migrations/20251112_r4.sql      && node scripts/run_sql.js scripts/migrations/20251112_r4.sql      || true
test -f scripts/migrations/20251112_r4b_ttl.sql && node scripts/run_sql.js scripts/migrations/20251112_r4b_ttl.sql || true

# r5 마이그레이션 (있으면)
test -f scripts/migrations/20251112_r5.sql      && node scripts/run_sql.js scripts/migrations/20251112_r5.sql      || true

echo "[9] 서버 재기동(r5; outbox 실패 유도 OFF)"
# 이전 프로세스 종료
test -f .petlink.pid && { PID=$(cat .petlink.pid || true); test -n "${PID:-}" && kill "$PID" 2>/dev/null || true; sleep 1; }

node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 2

echo "[10] 헬스체크"
for i in $(seq 1 20); do
  curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }
  sleep 0.3
  test "$i" -eq 20 && { echo "[ERR] 서버 무응답"; tail -n +1 .petlink.out || true; exit 1; }
done

echo "[11] r3 스모크(A~E)"
TOK="$(curl -s -XPOST "http://localhost:${PORT}/auth/signup" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
test -n "$TOK" || { echo "[ERR] 토큰 발급 실패"; exit 1; }

echo "  A) prefs"
curl -sf -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" "http://localhost:${PORT}/stores/1/channel-prefs" >/dev/null

echo "  B) 인보이스"
curl -sf -XPOST "http://localhost:${PORT}/billing/checkout" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}' >/dev/null

echo "  C) 초안 생성→발행"
curl -sf -XPOST "http://localhost:${PORT}/organic/drafts" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d '{"store_id":1,"copy":"상담/방문 안내","channels":["META","YOUTUBE"]}' >/dev/null

PUB="$(curl -s -XPOST "http://localhost:${PORT}/organic/drafts/1/publish" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1")" && echo "  C) publish OK"

echo "  D) 페이싱→인게스트"
MONTH="$(date +%Y-%m)"; TODAY="$(date +%Y-%m-%d)"
curl -sf -XPOST "http://localhost:${PORT}/pacer/apply" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d "{\"store_id\":1,\"month\":\"${MONTH}\",\"schedule\":[{\"date\":\"${TODAY}\",\"amount\":1000,\"min\":800,\"max\":1200}]}" >/dev/null

curl -sf -XPOST "http://localhost:${PORT}/ingest/META" -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" -d "[{\"ts\":\"$(date -u +%FT%TZ)\",\"store_id\":1,\"cost\":1300}]" >/dev/null || true

echo "  E) 시계열"
curl -sf "http://localhost:${PORT}/metrics/daily?days=3" >/dev/null || true

echo ""
echo "[12] r4 스모크(F~H)"
echo "  F) 멱등키 재시도"
K="idem-$(date +%s)"
curl -sf -D .idem1.h -o .idem1.b -XPOST "http://localhost:${PORT}/billing/checkout" \
 -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Idempotency-Key: ${K}" \
 -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}'

curl -sf -D .idem2.h -o .idem2.b -XPOST "http://localhost:${PORT}/billing/checkout" \
 -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Idempotency-Key: ${K}" \
 -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}'

if diff -q .idem1.b .idem2.b >/dev/null 2>&1 && grep -qi "X-Idempotent-Replay" .idem2.h 2>/dev/null; then
    echo "  F) IDEMPOTENCY REPLAY OK"
else
    echo "  F) IDEMPOTENCY REPLAY (부분 성공 또는 헤더 미표시)"
fi
rm -f .idem1.h .idem1.b .idem2.h .idem2.b || true

echo "  G) OpenAPI"
curl -sf "http://localhost:${PORT}/openapi.yaml" | grep -q "openapi:" && echo "  G) OPENAPI SPEC OK" || echo "  G) OPENAPI SPEC (확인 필요)"

curl -sf "http://localhost:${PORT}/docs" >/dev/null && echo "  G) SWAGGER UI OK" || echo "  G) SWAGGER UI (확인 필요)"

echo "  H) Outbox 관리"
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/outbox/peek" >/dev/null && echo "  H) OUTBOX PEEK OK" || echo "  H) OUTBOX PEEK (확인 필요)"

curl -sf -XPOST -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/outbox/flush" >/dev/null && echo "  H) OUTBOX FLUSH OK" || echo "  H) OUTBOX FLUSH (확인 필요)"

echo ""
echo "[13] r5 스모크(I~J)"
STAMP="$(date +%s)"
psql "$DATABASE_URL" -Atc "INSERT INTO idempotency_keys(key,method,path,req_hash,status,expire_at) VALUES ('exp-${STAMP}','POST','/demo','h','COMPLETED', now() - interval '1 day') ON CONFLICT (key) DO NOTHING;" 2>/dev/null || true

curl -sf -XPOST "http://localhost:${PORT}/admin/ops/housekeeping/run" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "  I) HOUSEKEEPING OK" || echo "  I) HOUSEKEEPING (확인 필요)"

CNT="$(psql "$DATABASE_URL" -Atc "SELECT count(*) FROM idempotency_keys WHERE key='exp-${STAMP}';" 2>/dev/null || echo "1")"
[ "$CNT" = "0" ] && echo "  I) TTL CLEANUP VERIFIED" || echo "  I) TTL CLEANUP (확인 필요: count=$CNT)"

curl -sf -XGET "http://localhost:${PORT}/admin/ops/dlq?limit=1" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && echo "  J) DLQ API OK" || echo "  J) DLQ API (확인 필요)"

echo ""
echo "[완료] 로그 확인:"
echo "  tail -f .petlink.out"
echo "  tail -f .outbox.log"
echo ""
echo "서버 포트: http://localhost:${PORT}"
echo "문서: http://localhost:${PORT}/docs"

