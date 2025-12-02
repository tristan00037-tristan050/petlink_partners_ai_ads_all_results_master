#!/usr/bin/env bash
set -euo pipefail

# ---------- 공통 환경 ----------
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export TIMEZONE="${TIMEZONE:-Asia/Seoul}"
export APP_HMAC="${APP_HMAC:-your-hmac-secret}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:5902,http://localhost:8000}"
export PORT="${PORT:-5902}"

# 스코프 잠금(검토팀 정책)
export ENABLE_CONSUMER_BILLING="false"
export ENABLE_ADS_BILLING="true"

# Billing 샌드박스(게이트 규정)
export BILLING_ADAPTER="${BILLING_ADAPTER:-mock}"     # mock | bootpay-sandbox
export BILLING_MODE="${BILLING_MODE:-sandbox}"
export PAYMENT_WEBHOOK_SECRET="${PAYMENT_WEBHOOK_SECRET:-dev-webhook-secret}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl

# ---------- Pre-flight(필수 4항목) ----------
echo "[PF] 필수 스크립트 확인"
test -f scripts/run_sql.js                         || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }
test -x scripts/go_live_r4r5_local.sh              || { echo "[ERR] scripts/go_live_r4r5_local.sh 누락"; exit 1; }

# execute_b2b_billing_roadmap.sh가 없으면 execute_scope_locked_gates.sh 사용
if [ ! -x scripts/execute_b2b_billing_roadmap.sh ]; then
  if [ -x scripts/execute_scope_locked_gates.sh ]; then
    echo "[PF] execute_b2b_billing_roadmap.sh 없음, execute_scope_locked_gates.sh 사용"
  else
    echo "[ERR] execute_b2b_billing_roadmap.sh 또는 execute_scope_locked_gates.sh 누락"; exit 1;
  fi
fi

echo "[PF] 어드민 미들웨어(requireAdmin) 시그니처 확인"
grep -q "requireAdmin" server/mw/admin.js 2>/dev/null || grep -q "requireAdmin" server/app.js 2>/dev/null || { echo "[ERR] requireAdmin 미탑재"; exit 1; }

echo "[PF] 보고용 테이블 가정 확인(없으면 최소 보완 적용)"

# 1) ad_creatives 최소 스키마(없을 때만 생성)
cat > .pf_min_ad_creatives.sql <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_creatives') THEN
    CREATE TABLE ad_creatives(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER,
      flags JSONB DEFAULT '{}'::jsonb,  -- { "forbidden_count": <int> }
      format_ok BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMPTZ DEFAULT now(),
      reviewed_at TIMESTAMPTZ,
      approved_at TIMESTAMPTZ
    );
  END IF;
END$$;
SQL

psql "$DATABASE_URL" -f .pf_min_ad_creatives.sql >/dev/null 2>&1 || true
rm -f .pf_min_ad_creatives.sql || true

# 2) outbox_dlq 뷰(테이블 dlq만 있고 outbox_dlq가 없을 때 대체 뷰 생성)
cat > .pf_min_outbox_dlq.sql <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='outbox_dlq')
     AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dlq') THEN
    CREATE OR REPLACE VIEW outbox_dlq AS
      SELECT id, topic, payload, reason, failed_at AS created_at FROM dlq;
  END IF;
END$$;
SQL

psql "$DATABASE_URL" -f .pf_min_outbox_dlq.sql >/dev/null 2>&1 || true
rm -f .pf_min_outbox_dlq.sql || true

echo "[PF] Node/psql/curl 사용 가능, 환경변수/시그니처/스키마 점검 완료"

# ---------- 실행(원클릭) ----------
echo "[EXEC] Gate 실행 스크립트 집행"
if [ -x scripts/execute_b2b_billing_roadmap.sh ]; then
  bash scripts/execute_b2b_billing_roadmap.sh | tee .gate_exec.log
else
  bash scripts/execute_scope_locked_gates.sh | tee .gate_exec.log
fi

# ---------- 결과 검증(공지의 성공 문자열) ----------
echo "[VERIFY] 성공 문자열 검증"
REQ_STRINGS=(
  # r4/r5 9/9
  "health OK" "IDEMPOTENCY REPLAY" "OPENAPI SPEC OK" "SWAGGER UI OK"
  "OUTBOX PEEK OK" "OUTBOX FLUSH OK" "HOUSEKEEPING" "TTL CLEANUP" "DLQ API"
  # B2B 파일럿 (필수 항목만)
  "PM ADD OK" "DOCS OPENAPI OK" "DOCS UI OK" "WEBHOOK NEGATIVE 401 OK" "DEPOSIT IMPORT OK"
  # Gate 통과
  "GATE-0" "GATE-1.PASS" "ALL GATES PASS"
)

MISSING=()
for s in "${REQ_STRINGS[@]}"; do
  grep -Fq "$s" .gate_exec.log || MISSING+=("$s")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "[ERR] 누락된 성공 문자열:"
  for m in "${MISSING[@]}"; do
    echo "  - $m"
    echo "    참고: grep -n \"$m\" .gate_exec.log"
  done
  exit 1
fi

echo
echo "[PASS] Gate-0/1/2 전 항목 통과"
echo "로그 확인: tail -n 200 .petlink.out"

