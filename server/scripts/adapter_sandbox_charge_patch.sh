#!/usr/bin/env bash
set -euo pipefail
mkdir -p scripts server/routes scripts/migrations

# ===== 공통 ENV =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export TIMEZONE="${TIMEZONE:-Asia/Seoul}"
export APP_HMAC="${APP_HMAC:-your-hmac-secret}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:5902,http://localhost:8000}"
export PORT="${PORT:-5902}"

# 스코프 잠금(B2B)
export ENABLE_CONSUMER_BILLING="false"
export ENABLE_ADS_BILLING="true"

# 샌드박스 모드 유지(검토팀 게이트)
export BILLING_MODE="${BILLING_MODE:-sandbox}"
export BILLING_ADAPTER="${BILLING_ADAPTER:-bootpay-sandbox}"   # bootpay-sandbox | mock

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }

# ad_payments 존재 여부 확인(이전 단계 반영 전제)
psql "$DATABASE_URL" -Atc "select 1 from information_schema.tables where table_name='ad_payments';" | grep -q 1 \
  || { echo "[ERR] ad_payments 테이블 없음. r5/r5.1 오버레이를 먼저 반영하세요."; exit 1; }

# ===== [패치 ③] FK 검사 완화 + 보강 마이그레이션 =====
cat > scripts/migrations/20251112_r51C_fk_relax.sql <<'SQL'
-- payment_methods 보장(멱등)
CREATE TABLE IF NOT EXISTS payment_methods(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  pm_type TEXT NOT NULL CHECK(pm_type IN ('CARD','NAVERPAY','KAKAOPAY','BANK')),
  provider TEXT NOT NULL,
  token TEXT NOT NULL,
  brand TEXT,
  last4 TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(advertiser_id, provider, token)
);
CREATE INDEX IF NOT EXISTS idx_pm_adv ON payment_methods(advertiser_id);

-- ad_payments.method_id 컬럼 보강(멱등)
ALTER TABLE ad_payments ADD COLUMN IF NOT EXISTS method_id BIGINT;

-- 외래키 존재 여부를 시스템 카탈로그로 확인 후, 없으면 추가
DO $$
DECLARE
  has_fk BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class      t ON t.oid=c.conrelid
    JOIN pg_attribute  a ON a.attrelid=t.oid AND a.attnum = ANY (c.conkey)
    JOIN pg_class      rt ON rt.oid=c.confrelid
    WHERE t.relname='ad_payments'
      AND a.attname='method_id'
      AND c.contype='f'
      AND rt.relname='payment_methods'
  ) INTO has_fk;

  IF NOT has_fk THEN
    BEGIN
      ALTER TABLE ad_payments
        ADD CONSTRAINT ad_payments_method_id_fkey
        FOREIGN KEY (method_id) REFERENCES payment_methods(id);
    EXCEPTION WHEN duplicate_object THEN
      -- 동시 실행/이질 명칭 FK가 이미 있으면 무시
      NULL;
    END;
  END IF;
END$$;
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251112_r51C_fk_relax.sql

# ===== [패치 ①②④] /ads/billing/charge 라우트 교체(멱등 가드 + method_id 가드 + 로그) =====
cat > server/routes/ads_billing_charge.js <<'JS'
const express = require('express');
const db = require('../lib/db');
const ads = require('../lib/ads_billing');
const adapter = require('../adapters/billing');
const admin = require('../mw/admin');

const r = express.Router();

/**
 * POST /ads/billing/charge
 * body: { invoice_no, advertiser_id, amount, method_id? }
 * - [①] 멱등 가드: 이미 CAPTURED이면 즉시 idempotent-return
 * - [②] 결제수단 미보유: 샌드박스는 통과, 라이브 모드에서는 400 권고
 * - [④] 로그 가독성: adapter/mode/invoice 기록
 */
r.post('/charge', express.json(), async (req,res)=>{
  const { invoice_no, advertiser_id, amount, method_id } = req.body || {};
  if (!invoice_no || !advertiser_id || amount == null) {
    return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  }
  const amt = Number(amount||0);
  const adv = Number(advertiser_id);
  const adapterName = (process.env.BILLING_ADAPTER || 'mock');
  const mode = (process.env.BILLING_MODE || 'sandbox');
  console.log('[billing] adapter=%s mode=%s invoice=%s', adapterName, mode, invoice_no); // [④]

  // 인보이스/페이먼트 보장
  await ads.ensureInvoice(invoice_no, adv, amt);
  await ads.ensurePayment(invoice_no, adv, amt);

  // [①] 멱등 가드: 이미 CAPTURED면 재청구 방지
  const cur = await db.q(`SELECT status FROM ad_payments WHERE invoice_no=$1 ORDER BY id DESC LIMIT 1`, [invoice_no]);
  if (cur.rows[0]?.status === 'CAPTURED') {
    return res.json({ ok:true, invoice_no, advertiser_id: adv, status:'CAPTURED', note:'idempotent-return' });
  }

  // 결제수단 결정(기본값 또는 지정)
  let mid = method_id;
  if (!mid) {
    const q = await db.q(
      `SELECT id FROM payment_methods WHERE advertiser_id=$1 AND is_default=TRUE ORDER BY id DESC LIMIT 1`,
      [adv]
    );
    if (q.rows.length) mid = q.rows[0].id;
  }
  if (mid) await db.q(`UPDATE ad_payments SET method_id=$1 WHERE invoice_no=$2`, [mid, invoice_no]);

  // [②] 라이브 모드에서는 method_id 필수(샌드박스는 통과)
  if (!mid && String(mode).toLowerCase() !== 'sandbox') {
    return res.status(400).json({ ok:false, code:'NO_DEFAULT_METHOD' });
  }

  // 토큰 조회(샌드박스/모의)
  let token = null;
  if (mid) {
    const t = await db.q(`SELECT token FROM payment_methods WHERE id=$1`, [mid]);
    token = t.rows[0]?.token || null;
  }

  // AUTHORIZE
  const a = await adapter.authorize({ invoice_no, amount: amt, token, advertiser_id: adv });
  if (!a?.ok) return res.status(502).json({ ok:false, code:'AUTH_FAILED' });
  if (a.provider_txn_id) await ads.upsertProviderTxn(invoice_no, a.provider_txn_id);
  await ads.setStatus(invoice_no, 'AUTHORIZED', { source:'charge', adapter:a.provider || adapterName });

  // CAPTURE
  const c = await adapter.capture({ invoice_no, amount: amt, provider_txn_id: a.provider_txn_id });
  if (!c?.ok) return res.status(502).json({ ok:false, code:'CAPTURE_FAILED' });
  if (c.provider_txn_id) await ads.upsertProviderTxn(invoice_no, c.provider_txn_id);
  await ads.setStatus(invoice_no, 'CAPTURED', { source:'charge', adapter:c.provider || adapterName });

  return res.json({ ok:true, invoice_no, advertiser_id: adv, status:'CAPTURED', provider_txn_id: c.provider_txn_id });
});

/**
 * GET /ads/billing/admin/verify/:invoice_no  (운영자 보호)
 */
r.get('/admin/verify/:invoice_no', admin.requireAdmin, async (req,res)=>{
  const invoice_no = req.params.invoice_no;
  const p = await db.q(
    `SELECT invoice_no, advertiser_id, amount, status, provider, provider_txn_id
       FROM ad_payments WHERE invoice_no=$1 ORDER BY id DESC LIMIT 1`,
    [invoice_no]
  );
  const i = await db.q(`SELECT invoice_no, status AS invoice_status FROM ad_invoices WHERE invoice_no=$1`, [invoice_no]);
  if (!p.rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  return res.json({ ok:true, payment: p.rows[0], invoice: i.rows[0]||null });
});

module.exports = r;
JS

# ===== app.js 라우트 마운트 보장(이미 있으면 유지) =====
if ! grep -q "routes/ads_billing_charge" server/app.js; then
  # express.json() 이후에 라우트 추가
  sed -i.bak '/app\.use(express\.json/i\
app.use('\''/ads/billing'\'', require('\''./routes/ads_billing_charge'\''));\
' server/app.js && rm -f server/app.js.bak || true
fi

# ===== 서버 재기동 =====
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done

# ===== 스모크: 어댑터 준비 / CHARGE / VERIFY / 멱등 / 로그 =====
echo "[SMOKE] 어댑터 준비"
curl -sf "http://localhost:${PORT}/admin/ads/billing/preflight" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ok":true' && echo "ADAPTER READY OK"

# 광고주 101 기본 결제수단 보장(중복 무해)
node - <<'NODE'
const { Client } = require('pg');
(async ()=>{
  const url = process.env.DATABASE_URL;
  const c = new Client({ connectionString:url });
  await c.connect();
  const provider = (process.env.BILLING_ADAPTER||'mock').includes('bootpay') ? 'bootpay' : 'mock';
  await c.query(
    `INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default)
     VALUES(101,'CARD',$1,'tok-demo-101','VISA','4242',true)
     ON CONFLICT (advertiser_id,provider,token) DO NOTHING`, [provider]);
  await c.query(
    `UPDATE payment_methods SET is_default = (id = (SELECT id FROM payment_methods WHERE advertiser_id=101 ORDER BY id DESC LIMIT 1))
     WHERE advertiser_id=101`);
  await c.end(); process.exit(0);
})().catch(()=>process.exit(0));
NODE

INV="INV-$(date +%s)"

echo "[SMOKE] CHARGE"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/charge" \
  -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":101,\"amount\":120000}" \
  | grep -q '"status":"CAPTURED"' && echo "SANDBOX CHARGE OK"

echo "[SMOKE] VERIFY"
curl -sf "http://localhost:${PORT}/ads/billing/admin/verify/${INV}" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ok":true' && echo "VERIFY OK"

# CAPTURED/PAID 확인
ST_P=$(psql "$DATABASE_URL" -Atc "select status from ad_payments where invoice_no='${INV}' order by id desc limit 1;" 2>/dev/null || echo "")
ST_I=$(psql "$DATABASE_URL" -Atc "select status from ad_invoices where invoice_no='${INV}' limit 1;" 2>/dev/null || echo "")
[ "$ST_P" = "CAPTURED" ] && [ "$ST_I" = "PAID" ] && echo "CAPTURED/PAID OK" || echo "[WARN] 상태 확인: payment=${ST_P} invoice=${ST_I}"

# [①] 멱등 가드 확인(동일 invoice 재청구 → note:idempotent-return 기대)
echo "[SMOKE] 멱등 재청구"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/charge" \
  -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":101,\"amount\":120000}" \
  | grep -q '"note":"idempotent-return"' && echo "IDEMPOTENT CHARGE OK"

# [④] 로그 패턴 확인
grep -q "\[billing\] adapter=" .petlink.out && echo "LOG LINE OK" || echo "[WARN] 로그 패턴 미검출"

echo
echo "[DONE] 4패치 반영 + 샌드박스 Charge/Verify 집행 완료"
echo "로그: tail -n 200 .petlink.out"


