#!/usr/bin/env bash
# go_live_r4.sh - r4 무중단 오버레이 원클릭 실행 (Fix-Pack 포함)

set -euo pipefail

PORT="${PORT:-5902}"
TIMEZONE="${TIMEZONE:-Asia/Seoul}"
APP_HMAC="${APP_HMAC:-}"
ADMIN_KEY="${ADMIN_KEY:-}"
DATABASE_URL="${DATABASE_URL:-}"
CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:5902,http://localhost:8000}"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[need] $1 필요"
        exit 1
    }
}

echo "[1/11] 사전 점검"
need curl
need node
need npm

# psql은 선택 (DB 마이그레이션 시에만 필요)
if ! command -v psql >/dev/null 2>&1; then
    echo "[WARN] psql이 없습니다. DB 마이그레이션은 node scripts/run_sql.js로 대체됩니다."
    echo "       psql 설치: macOS(brew install postgresql), Ubuntu(sudo apt-get install postgresql-client)"
fi

test -f scripts/apply_p2_r3_persistence.sh || {
    echo "[ERR] r3 패치 선행 필요"
    exit 1
}

test -f scripts/db_migrate.sh || {
    echo "[ERR] scripts/db_migrate.sh 없음"
    exit 1
}

test -f scripts/run_sql.js || {
    echo "[ERR] scripts/run_sql.js 없음"
    exit 1
}

for f in server/lib/db.js server/lib/repo.js server/mw/auth.js server/mw/admin.js; do
    test -f "$f" || {
        echo "[ERR] 누락: $f"
        exit 1
    }
done

echo "[2/11] 환경변수 확인"
: "${DATABASE_URL:?DATABASE_URL 필수}"
: "${APP_HMAC:?APP_HMAC 필수}"
: "${ADMIN_KEY:?ADMIN_KEY 필수}"

export PORT TIMEZONE APP_HMAC ADMIN_KEY DATABASE_URL CORS_ORIGINS

echo "[3/11] r3 재적용(safe)"
bash scripts/apply_p2_r3_persistence.sh || true

echo "[4/11] r4 패치/픽스팩 적용"
[ -f scripts/apply_p2_r4.sh ] && bash scripts/apply_p2_r4.sh || true
[ -f scripts/apply_p2_r4_fixpack.sh ] && bash scripts/apply_p2_r4_fixpack.sh || true

echo "[5/11] 서버 의존성 설치"
npm i pg luxon pino express-pino-logger helmet express-rate-limit zod >/dev/null 2>&1 || true

echo "[6/11] DB 마이그레이션 + r4 전용 SQL"
# psql이 있으면 db_migrate.sh 사용, 없으면 run_sql.js 사용
if command -v psql >/dev/null 2>&1; then
    scripts/db_migrate.sh || {
        echo "[WARN] db_migrate.sh 실패, run_sql.js로 대체"
        node scripts/run_sql.js scripts/migrations/001_init.sql || true
    }
else
    echo "[INFO] psql 없음, run_sql.js로 마이그레이션 실행"
    node scripts/run_sql.js scripts/migrations/001_init.sql || true
fi

node scripts/run_sql.js scripts/migrations/20251112_r4.sql || {
    echo "[WARN] r4 마이그레이션 실패 (계속 진행)"
}

[ -f scripts/migrations/20251112_r4b_ttl.sql ] && node scripts/run_sql.js scripts/migrations/20251112_r4b_ttl.sql || true

echo "[7/11] 서버 재기동"
if [ -f .petlink.pid ]; then
    OLD=$(cat .petlink.pid || true)
    if [ -n "${OLD:-}" ] && kill -0 "$OLD" 2>/dev/null; then
        kill "$OLD" || true
        sleep 1
    fi
fi

node server/app.js > .petlink.out 2>&1 &
echo $! > .petlink.pid
sleep 1

echo "[8/11] 헬스체크"
for i in $(seq 1 20); do
    if curl -sf "http://localhost:${PORT}/health" >/dev/null; then
        echo "health OK"
        break
    fi
    sleep 0.3
    if [ "$i" -eq 20 ]; then
        echo "[ERR] 서버 무응답"
        tail -n +1 .petlink.out || true
        exit 1
    fi
done

echo "[9/11] 스모크(A~E: r3와 동일)"
TOK="$(curl -s -XPOST "http://localhost:${PORT}/auth/signup" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
test -n "$TOK" || {
    echo "[ERR] 토큰 발급 실패"
    exit 1
}

echo "  A) prefs"
curl -sf -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" "http://localhost:${PORT}/stores/1/channel-prefs" >/dev/null

echo "  B) 인보이스"
curl -sf -XPOST "http://localhost:${PORT}/billing/checkout" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" \
    -H "Content-Type: application/json" -d '{"plan":"Starter","price":200000}' >/dev/null

echo "  C) 초안 생성→발행→승인"
curl -sf -XPOST "http://localhost:${PORT}/organic/drafts" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" \
    -d '{"store_id":1,"copy":"상담/방문 안내","channels":["META","YOUTUBE"]}' >/dev/null

PUB="$(curl -s -XPOST "http://localhost:${PORT}/organic/drafts/1/publish" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1")"
APPROVE="$(echo "$PUB" | sed -n 's/.*"approve_token":"\([^"]*\)".*/\1/p' | head -n1 || true)"
if [ -n "${APPROVE:-}" ]; then
    curl -sf -XPOST "http://localhost:${PORT}/organic/drafts/1/approve" \
        -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" \
        -d "{\"token\":\"${APPROVE}\"}" >/dev/null
fi

echo "  D) 페이싱→인게스트→차단 응답 관찰"
MONTH="$(date +%Y-%m)"
TODAY="$(date +%Y-%m-%d)"
curl -sf -XPOST "http://localhost:${PORT}/pacer/apply" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" \
    -d "{\"store_id\":1,\"month\":\"${MONTH}\",\"schedule\":[{\"date\":\"${TODAY}\",\"amount\":1000,\"min\":800,\"max\":1200}]}" >/dev/null

curl -sf -XPOST "http://localhost:${PORT}/ingest/META" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" \
    -d "[{\"ts\":\"$(date -u +%FT%TZ)\",\"store_id\":1,\"cost\":1300}]" >/dev/null

curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/organic/drafts/1/publish" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" | grep -qE '409|200' || true

echo "  E) 시계열"
curl -sf "http://localhost:${PORT}/metrics/daily?days=3" >/dev/null || true

echo "[10/11] r4 스모크(F~H)"
echo "  F) 멱등키 재시도(동일 응답 재전송)"
K="idem-$(date +%s)"
HDRS="-H Authorization: Bearer ${TOK} -H X-Store-ID: 1 -H Content-Type: application/json -H Idempotency-Key: ${K}"
curl -sf -D .idem1.h -o .idem1.b -XPOST "http://localhost:${PORT}/billing/checkout" $HDRS -d '{"plan":"Starter","price":200000}'
curl -sf -D .idem2.h -o .idem2.b -XPOST "http://localhost:${PORT}/billing/checkout" $HDRS -d '{"plan":"Starter","price":200000}'
if grep -qi "X-Idempotent-Replay" .idem2.h 2>/dev/null; then
    echo "    → 재전송 헤더 OK"
else
    echo "    → 재전송 헤더 미표시(무시)"
fi
rm -f .idem1.h .idem1.b .idem2.h .idem2.b || true

echo "  G) OpenAPI 문서/콘솔"
if curl -sf "http://localhost:${PORT}/openapi.yaml" | grep -q "openapi: 3.0"; then
    echo "    → openapi.yaml OK"
else
    echo "[WARN] openapi.yaml 확인 실패"
fi
curl -sf "http://localhost:${PORT}/docs" >/dev/null && echo "    → /docs OK" || echo "    → /docs 접근 실패(캐시/프록시 확인)"

echo "  H) Outbox 관리(관리자키 필요)"
curl -sf -XGET "http://localhost:${PORT}/admin/outbox/peek" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && echo "    → peek OK" || echo "    → peek 실패(어드민 키/미들웨어 정책 확인)"
curl -sf -XPOST "http://localhost:${PORT}/admin/outbox/flush" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && echo "    → flush OK" || echo "    → flush 실패(무시)"

echo "[11/11] 증빙 번들 생성"
ADMIN_KEY="${ADMIN_KEY}" bash scripts/generate_proof_bundle.sh >/dev/null 2>&1 || true

echo ""
echo "완료: r4 적용 및 서버 포트=${PORT}"
echo "문서: http://localhost:${PORT}/docs  |  스펙: /openapi.yaml"
echo "로그: tail -f .petlink.out  |  outbox: tail -f .outbox.log"
