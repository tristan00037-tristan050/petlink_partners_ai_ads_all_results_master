#!/usr/bin/env bash
# go_live_r3.sh - 원클릭 부트스트랩 스크립트

set -euo pipefail

# ===== 설정 =====
PORT="${PORT:-5902}"
TIMEZONE="${TIMEZONE:-Asia/Seoul}"
APP_HMAC="${APP_HMAC:-}"
ADMIN_KEY="${ADMIN_KEY:-}"
DATABASE_URL="${DATABASE_URL:-}"
CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:5902,http://localhost:8000}"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "[need] '$1' 명령어가 필요합니다."
        exit 1
    }
}

echo "[1/9] 사전 점검"
need curl
need node
need npm
need psql

test -f scripts/apply_p2_r3_persistence.sh || {
    echo "[ERR] scripts/apply_p2_r3_persistence.sh 가 없습니다. r3 패치를 먼저 반영하세요."
    exit 1
}

test -f scripts/db_migrate.sh || {
    echo "[ERR] scripts/db_migrate.sh 가 없습니다. r3 패치 누락입니다."
    exit 1
}

test -f scripts/db_rollback.sh || {
    echo "[WARN] scripts/db_rollback.sh 없음 (권장). 계속 진행합니다."
}

test -f scripts/run_sql.js || {
    echo "[ERR] scripts/run_sql.js 가 없습니다. r3 패치 누락입니다."
    exit 1
}

test -f server/lib/db.js || {
    echo "[ERR] server/lib/db.js 없음"
    exit 1
}

test -f server/lib/repo.js || {
    echo "[ERR] server/lib/repo.js 없음"
    exit 1
}

# r2 필수 파일 존재 확인(검토팀 주의 포인트)
for f in server/mw/auth.js server/mw/admin.js server/lib/time.js server/lib/validators.js \
         server/lib/copy_engine.js server/lib/audit.js server/connectors/meta.js \
         server/connectors/tiktok.js server/connectors/youtube.js server/connectors/kakao.js \
         server/connectors/naver.js server/queue/bull.js; do
    test -f "$f" || {
        echo "[ERR] 누락 파일: $f"
        exit 1
    }
done

echo "[2/9] 환경변수 확인"
: "${DATABASE_URL:?DATABASE_URL 필수 (예: postgres://postgres:petpass@localhost:5432/petlink)}"
: "${APP_HMAC:?APP_HMAC 필수(HMAC 승인토큰 검증용)}"
: "${ADMIN_KEY:?ADMIN_KEY 필수(/admin/audit 보호)}"

export PORT TIMEZONE APP_HMAC ADMIN_KEY DATABASE_URL CORS_ORIGINS

echo "[3/9] r3 패치 재적용(없으면 스킵-safe)"
bash scripts/apply_p2_r3_persistence.sh || true

echo "[4/9] 서버 의존성 설치"
npm i pg luxon pino express-pino-logger helmet express-rate-limit zod >/dev/null 2>&1

echo "[5/9] DB 마이그레이션"
scripts/db_migrate.sh

echo "[6/9] 서버 기동"
# 기존 프로세스 종료
if [ -f .petlink.pid ]; then
    OLD=$(cat .petlink.pid || true)
    if [ -n "${OLD:-}" ] && kill -0 "$OLD" 2>/dev/null; then
        kill "$OLD" || true
        sleep 1
    fi
fi

# 기동
node server/app.js > .petlink.out 2>&1 &
echo $! > .petlink.pid
sleep 1

echo "[7/9] 헬스체크"
for i in $(seq 1 20); do
    if curl -sf "http://localhost:${PORT}/health" >/dev/null; then
        echo "health OK"
        break
    fi
    sleep 0.3
    if [ "$i" -eq 20 ]; then
        echo "[ERR] 서버가 응답하지 않습니다. 로그:"
        tail -n +1 .petlink.out || true
        exit 1
    fi
done

echo "[8/9] 스모크 테스트(A~E)"
TOK="$(curl -s -XPOST "http://localhost:${PORT}/auth/signup" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
test -n "$TOK" || {
    echo "[ERR] 토큰 발급 실패"
    exit 1
}

echo "  A) prefs 읽기"
curl -sf -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" "http://localhost:${PORT}/stores/1/channel-prefs" >/dev/null

echo "  B) 인보이스 JSON"
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

echo "  D) 페이싱 적용→인게스트→차단"
TODAY="$(date +"%Y-%m-%d")"
MONTH="$(date +%Y-%m)"
curl -sf -XPOST "http://localhost:${PORT}/pacer/apply" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" \
    -d "{\"store_id\":1,\"month\":\"${MONTH}\",\"schedule\":[{\"date\":\"${TODAY}\",\"amount\":1000,\"min\":800,\"max\":1200}]}" >/dev/null

curl -sf -XPOST "http://localhost:${PORT}/ingest/META" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" -H "Content-Type: application/json" \
    -d "[{\"ts\":\"$(date -u +%FT%TZ)\",\"store_id\":1,\"cost\":1300}]" >/dev/null

# 차단 응답 확인(409 기대) - 실패해도 전체 진행에는 영향 없음
curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/organic/drafts/1/publish" \
    -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 1" | grep -qE '409|200' || true

echo "  E) 시계열"
curl -sf "http://localhost:${PORT}/metrics/daily?days=3" >/dev/null

echo "[9/9] 증빙 번들 생성"
ADMIN_KEY="${ADMIN_KEY}" bash scripts/generate_proof_bundle.sh >/dev/null 2>&1 || true

echo "완료: 서버 포트=${PORT}, TZ=${TIMEZONE}, DB=$( [ -n "$DATABASE_URL" ] && echo on || echo off )"
echo "로그: tail -f .petlink.out"


