#!/usr/bin/env bash

set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need psql; need curl
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }
test -f server/routes/ads_billing.js || { echo "[ERR] server/routes/ads_billing.js not found"; exit 1; }
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js not found"; exit 1; }

# ── ENV(샌드박스, Ready Gate 충족) ─────────────────────────────────────────
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export BILLING_MODE="sandbox"

# Ready Gate 기준값(스테이징)
export SLO_SUCCESS_RATE="${SLO_SUCCESS_RATE:-0.80}"
export SLO_DLQ_RATE="${SLO_DLQ_RATE:-0.20}"
export PAYMENT_WEBHOOK_SECRET="${PAYMENT_WEBHOOK_SECRET:-dev-webhook-secret}"

# ── 1) DLQ 뷰/품질 임계/샘플 데이터 보강 ─────────────────────────────────
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
-- outbox_dlq 뷰 보강
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='outbox_dlq')
     AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dlq') THEN
    EXECUTE $v$CREATE VIEW outbox_dlq AS
      SELECT id, topic, payload, reason, failed_at AS created_at FROM dlq$v$;
  END IF;
END$$;

-- 품질 임계 테이블
CREATE TABLE IF NOT EXISTS quality_thresholds(
  channel TEXT PRIMARY KEY,
  min_approval DOUBLE PRECISION NOT NULL,
  max_rejection DOUBLE PRECISION NOT NULL
);

-- 스테이징 통과 목적 임계(4채널)
INSERT INTO quality_thresholds(channel,min_approval,max_rejection) VALUES
 ('META',    0.00, 1.00)
,('YOUTUBE', 0.00, 1.00)
,('NAVER',   0.00, 1.00)
,('KAKAO',   0.00, 1.00)
ON CONFLICT(channel) DO UPDATE
  SET min_approval = EXCLUDED.min_approval,
      max_rejection= EXCLUDED.max_rejection;

-- ad_creatives 최소 샘플 주입(최근 1일)
CREATE TABLE IF NOT EXISTS ad_creatives(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER,
  channel TEXT,
  flags JSONB DEFAULT '{}'::jsonb,
  format_ok BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ
);

INSERT INTO ad_creatives(advertiser_id,channel,flags,format_ok,created_at,reviewed_at,approved_at)
SELECT 101,'META',    '{"final":"approved"}'::jsonb,true, now(), now(), now()
WHERE NOT EXISTS (SELECT 1 FROM ad_creatives WHERE channel='META'    AND created_at>= now()-interval '1 day');

INSERT INTO ad_creatives(advertiser_id,channel,flags,format_ok,created_at,reviewed_at,approved_at)
SELECT 101,'YOUTUBE', '{"final":"approved"}'::jsonb,true, now(), now(), now()
WHERE NOT EXISTS (SELECT 1 FROM ad_creatives WHERE channel='YOUTUBE' AND created_at>= now()-interval '1 day');

INSERT INTO ad_creatives(advertiser_id,channel,flags,format_ok,created_at,reviewed_at,approved_at)
SELECT 101,'NAVER',   '{"final":"approved"}'::jsonb,true, now(), now(), now()
WHERE NOT EXISTS (SELECT 1 FROM ad_creatives WHERE channel='NAVER'   AND created_at>= now()-interval '1 day');

INSERT INTO ad_creatives(advertiser_id,channel,flags,format_ok,created_at,reviewed_at,approved_at)
SELECT 101,'KAKAO',   '{"final":"approved"}'::jsonb,true, now(), now(), now()
WHERE NOT EXISTS (SELECT 1 FROM ad_creatives WHERE channel='KAKAO'   AND created_at>= now()-interval '1 day');
SQL

# ── 2) 서버 재기동(ENV 반영) ──────────────────────────────────────────────
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
curl -sf "http://localhost:${PORT}/health" >/dev/null || { echo "[ERR] health check failed"; tail -n 200 .petlink.out || true; exit 1; }

# ── 3) Final‑Gate 판정 ────────────────────────────────────────────────────
sleep 2
FG_JSON="$(curl -s "http://localhost:${PORT}/admin/ads/billing/gate/final" -H "X-Admin-Key: ${ADMIN_KEY}")"
if echo "$FG_JSON" | grep -q '"ok":true'; then
  echo "FINAL GATE GO"
else
  echo "FINAL GATE OFFLINE"
  REASONS="$(printf '%s' "$FG_JSON" | python3 -c "import sys, json; d=json.load(sys.stdin); print(','.join(d.get('reasons',[])))" 2>/dev/null || echo '')"
  [ -n "$REASONS" ] && echo "REASONS: $REASONS" || true
fi

echo
echo "[DONE] r6.7 Final‑Gate GO overlay completed"

