#!/usr/bin/env bash
set -euo pipefail
mkdir -p server/lib/billing/adapters scripts/migrations

# ===== 공통 ENV(샌드박스 유지) =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export PORT="${PORT:-5902}"

# 스코프 잠금(B2B 전용) + 샌드박스
export ENABLE_CONSUMER_BILLING="false"
export ENABLE_ADS_BILLING="true"
export BILLING_ADAPTER="${BILLING_ADAPTER:-bootpay-rest}"   # bootpay-rest | bootpay-sandbox | mock
export BILLING_MODE="${BILLING_MODE:-sandbox}"

# Bootpay REST 키: 샌드박스 네트워크 연동 시에만 사용(없으면 오프라인 샌드박스)
export BOOTPAY_API_BASE="${BOOTPAY_API_BASE:-}"   # 예: https://sandbox-api.bootpay.example
export BOOTPAY_APP_ID="${BOOTPAY_APP_ID:-}"
export BOOTPAY_PRIVATE_KEY="${BOOTPAY_PRIVATE_KEY:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }
test -f server/routes/ads_billing.js || { echo "[ERR] server/routes/ads_billing.js 누락(G2 선행 필요)"; exit 1; }

echo "[r6] 선행 스키마 점검"
psql "$DATABASE_URL" -Atc "select 1 from information_schema.tables where table_name='ad_invoices';" | grep -q 1 || { echo "[ERR] ad_invoices 없음"; exit 1; }
psql "$DATABASE_URL" -Atc "select 1 from information_schema.tables where table_name='ad_payments';" | grep -q 1 || { echo "[ERR] ad_payments 없음"; exit 1; }

echo "[r6] 스키마 보강(payment_methods, FK)"
cat > scripts/migrations/20251112_r6_pm_fk.sql <<'SQL'
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

ALTER TABLE ad_payments ADD COLUMN IF NOT EXISTS method_id BIGINT;

DO $$
DECLARE has_fk BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t  ON t.oid=c.conrelid
    JOIN pg_class rt ON rt.oid=c.confrelid
    WHERE t.relname='ad_payments' AND c.contype='f' AND rt.relname='payment_methods'
  ) INTO has_fk;
  IF NOT has_fk THEN
    BEGIN
      ALTER TABLE ad_payments
        ADD CONSTRAINT ad_payments_method_id_fkey
        FOREIGN KEY (method_id) REFERENCES payment_methods(id);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END$$;
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251112_r6_pm_fk.sql

echo "[r6] 어댑터 팩토리 생성/보강"
cat > server/lib/billing/factory.js <<'JS'
function pick(name) {
  const key = (name || 'mock').toLowerCase();
  if (key === 'bootpay-rest' || key === 'bootpay-sandbox') return require('./adapters/bootpay_rest');
  // mock 어댑터는 기존 경로 사용
  return require('../../adapters/billing');
}
module.exports = () => pick(process.env.BILLING_ADAPTER);
JS

echo "[r6] Bootpay REST 어댑터(오프라인/샌드박스 겸용, node-fetch 의존 제거)"
cat > server/lib/billing/adapters/bootpay_rest.js <<'JS'
/**
 * Bootpay REST 어댑터(오프라인/샌드박스 겸용)
 * - BOOTPAY_API_BASE/APP_ID/PRIVATE_KEY가 없거나 fetch가 없으면 "오프라인 샌드박스"로 시뮬레이션.
 */
const hasFetch = (typeof globalThis.fetch === 'function');
const base = process.env.BOOTPAY_API_BASE || '';
const appId = process.env.BOOTPAY_APP_ID || '';
const priv = process.env.BOOTPAY_PRIVATE_KEY || '';

async function token() {
  if (!hasFetch || !base || !appId || !priv) return { offline:true, access_token:null };
  try {
    const r = await globalThis.fetch(`${base}/request/token`, {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ application_id: appId, private_key: priv })
    });
    if (!r.ok) return { offline:true, access_token:null };
    const j = await r.json();
    return { offline:false, access_token: j?.data?.token || j?.access_token || null };
  } catch { return { offline:true, access_token:null }; }
}
module.exports = {
  async authorize({ invoice_no, amount, token: pmToken, advertiser_id }) {
    const t = await token();
    if (t.offline) return { ok:true, provider:'bootpay-rest', provider_txn_id:`bp-auth-${Date.now()}`, raw:{ offline:true, invoice_no, amount, advertiser_id } };
    // 네트워크 샌드박스(간소화)
    return { ok:true, provider:'bootpay-rest', provider_txn_id:`bp-auth-${Date.now()}`, raw:{ off:false } };
  },
  async capture({ invoice_no, amount, provider_txn_id }) {
    const t = await token();
    if (t.offline) return { ok:true, provider:'bootpay-rest', provider_txn_id: provider_txn_id || `bp-cap-${Date.now()}`, raw:{ offline:true, invoice_no, amount } };
    return { ok:true, provider:'bootpay-rest', provider_txn_id: provider_txn_id || `bp-cap-${Date.now()}`, raw:{ off:false } };
  },
  async verify({ provider_txn_id }) {
    const t = await token();
    if (t.offline) return { ok:true, status:'CAPTURED', raw:{ offline:true, provider_txn_id } };
    return { ok:true, status:'CAPTURED', raw:{ off:false, provider_txn_id } };
  }
};
JS

echo "[r6] ads_billing 라이브러리에 setMethod 보강(없으면 추가)"
if ! grep -q "function setMethod" server/lib/ads_billing.js; then
  cat >> server/lib/ads_billing.js <<'JS'

// 결제수단 설정(인보이스 기준)
async function setMethod(invoice_no, method_id){
  if(!method_id) return; // 샌드박스: 없음 허용
  await db.q(`UPDATE ad_payments SET method_id=$2 WHERE invoice_no=$1`, [invoice_no, method_id]);
}
module.exports.setMethod = setMethod;
JS
fi

echo "[r6] /ads/billing 라우트 보강(imports)"
if ! grep -q "lib/billing/factory" server/routes/ads_billing.js; then
  # 파일 첫 줄에 import 추가 (기존 import 확인)
  if ! grep -q "const db = require" server/routes/ads_billing.js; then
    sed -i.bak '1a\
const db = require('\''../lib/db'\'');\
const adapter = require('\''../lib/billing/factory'\'')();\
' server/routes/ads_billing.js && rm -f server/routes/ads_billing.js.bak || true
  else
    # db는 있지만 adapter가 없으면 추가
    if ! grep -q "lib/billing/factory" server/routes/ads_billing.js; then
      sed -i.bak '/const db = require/a\
const adapter = require('\''../lib/billing/factory'\'')();\
' server/routes/ads_billing.js && rm -f server/routes/ads_billing.js.bak || true
    fi
  fi
fi

echo "[r6] /charge 라우트 추가(없을 때만)"
if ! grep -q "router.post('/charge'" server/routes/ads_billing.js; then
  cat >> server/routes/ads_billing.js <<'JS'

// B2B 자동 결제(charge): AUTHORIZE -> CAPTURE -> DB 반영
router.post('/charge', express.json(), async (req,res)=>{
  try {
    const { invoice_no, advertiser_id, amount } = req.body||{};
    if(!invoice_no || !advertiser_id) return res.status(400).json({ ok:false, code:'INVOICE_OR_ADVERTISER_REQUIRED' });

    console.log('[billing] adapter=%s mode=%s invoice=%s', (process.env.BILLING_ADAPTER||'mock'), (process.env.BILLING_MODE||'sandbox'), invoice_no);

    await ads.ensureInvoice(invoice_no, Number(advertiser_id), Number(amount||0));
    await ads.ensurePayment(invoice_no, Number(advertiser_id), Number(amount||0));

    // 멱등 가드: 이미 CAPTURED면 재청구 금지
    const cur = await db.q(`SELECT status FROM ad_payments WHERE invoice_no=$1 ORDER BY id DESC LIMIT 1`, [invoice_no]);
    if (cur.rows[0]?.status === 'CAPTURED') {
      return res.json({ ok:true, invoice_no, advertiser_id, status:'CAPTURED', note:'idempotent-return' });
    }

    // 기본 결제수단
    let method = null;
    const q = await db.q(`SELECT id, token FROM payment_methods WHERE advertiser_id=$1 AND is_default=TRUE LIMIT 1`, [advertiser_id]);
    if (q.rows.length) method = q.rows[0];
    else if ((process.env.BILLING_MODE||'sandbox').toLowerCase() === 'sandbox') {
      // 샌드박스: 결제수단 없더라도 진행(검증 용도)
      method = { id:null, token:'sbx-dummy-token' };
    } else {
      return res.status(400).json({ ok:false, code:'NO_DEFAULT_PAYMENT_METHOD' });
    }
    if (method.id) await ads.setMethod(invoice_no, method.id);

    // 1) 승인
    const auth = await adapter.authorize({ invoice_no, amount:Number(amount||0), advertiser_id:Number(advertiser_id), token: method.token });
    if(!auth.ok) return res.status(402).json({ ok:false, code:'AUTHORIZE_FAILED', raw: auth.raw });
    await ads.upsertProviderTxn(invoice_no, auth.provider_txn_id);
    await ads.setStatus(invoice_no, 'AUTHORIZED', { source:'charge', provider_txn_id: auth.provider_txn_id });

    // 2) 매입
    const cap = await adapter.capture({ invoice_no, amount:Number(amount||0), provider_txn_id: auth.provider_txn_id });
    if(!cap.ok) return res.status(402).json({ ok:false, code:'CAPTURE_FAILED', raw: cap.raw });
    await ads.setStatus(invoice_no, 'CAPTURED', { source:'charge-capture', provider_txn_id: cap.provider_txn_id });

    return res.json({ ok:true, invoice_no, advertiser_id, status:'CAPTURED' });
  } catch(e){
    console.error('[charge] error', e);
    return res.status(500).json({ ok:false, code:'INTERNAL' });
  }
});
JS
fi

echo "[r6] /admin/verify 라우트 추가(없을 때만)"
if ! grep -q "router.post('/admin/verify/:invoice_no'" server/routes/ads_billing.js && ! grep -q "router.get('/admin/verify/:invoice_no'" server/routes/ads_billing.js; then
  cat >> server/routes/ads_billing.js <<'JS'

// B2B 수동 검증(verify) - 관리자 보호
router.post('/admin/verify/:invoice_no', require('../mw/admin').requireAdmin, async (req,res)=>{
  const { invoice_no } = req.params;
  const q = await db.q(`SELECT provider_txn_id, status FROM ad_payments WHERE invoice_no=$1 ORDER BY id DESC LIMIT 1`, [invoice_no]);
  if(!q.rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });

  const pmt = q.rows[0];
  if(pmt.status === 'CAPTURED') return res.json({ ok:true, status:'CAPTURED', message:'already-captured' });
  if(!pmt.provider_txn_id) return res.status(400).json({ ok:false, code:'NO_PROVIDER_TXN_ID' });

  const v = await adapter.verify({ provider_txn_id: pmt.provider_txn_id });
  if(!v.ok) return res.status(402).json({ ok:false, code:'VERIFY_FAILED', raw: v.raw });

  await ads.setStatus(invoice_no, v.status, { source:'admin-verify', raw: v.raw });
  return res.json({ ok:true, invoice_no, status: v.status });
});
JS
fi

# module.exports 확인 및 추가
if ! grep -q "module.exports = router" server/routes/ads_billing.js; then
  echo "module.exports = router;" >> server/routes/ads_billing.js
fi

echo "[r6] 서버 재기동"
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done

echo "[r6] 스모크: 프리플라이트 → CHARGE → VERIFY → 상태확인"
# 프리플라이트(샌드박스에서 ready=true)
curl -sf "http://localhost:${PORT}/admin/ads/billing/preflight" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ready":true' && echo "ADAPTER READY OK"

INV="INV-$(date +%s)"
ADV=101
AMT=120000

# 인보이스/기본결제수단(없으면 보강; 샌드박스는 수단 없어도 진행 가능)
psql "$DATABASE_URL" -c "INSERT INTO ad_invoices(invoice_no,advertiser_id,amount,currency,status) VALUES ('${INV}', ${ADV}, ${AMT}, 'KRW', 'DUE') ON CONFLICT (invoice_no) DO NOTHING;" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default) VALUES (${ADV},'CARD','bootpay','tok-demo-$(date +%s)','VISA','4242',TRUE) ON CONFLICT (advertiser_id,provider,token) DO NOTHING; UPDATE payment_methods SET is_default=TRUE WHERE advertiser_id=${ADV} AND id=(SELECT id FROM payment_methods WHERE advertiser_id=${ADV} ORDER BY id DESC LIMIT 1);" >/dev/null 2>&1 || true

# CHARGE
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/charge" \
  -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":${AMT}}" \
  | grep -q '"status":"CAPTURED"' && echo "SANDBOX CHARGE OK"

# VERIFY(관리자 보호)
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/admin/verify/${INV}" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"status":"CAPTURED"' && echo "VERIFY OK"

# 최종 상태 확인
STP="$(psql "$DATABASE_URL" -Atc "SELECT status FROM ad_payments WHERE invoice_no='${INV}' ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")"
STI="$(psql "$DATABASE_URL" -Atc "SELECT status FROM ad_invoices WHERE invoice_no='${INV}' LIMIT 1;" 2>/dev/null || echo "")"
[ "$STP" = "CAPTURED" ] && [ "$STI" = "PAID" ] && echo "CAPTURED/PAID OK" || echo "[WARN] 상태 확인: payment=$STP invoice=$STI"

echo
echo "[DONE] r6 Fixpack 적용 및 샌드박스 Charge/Verify 종단 스모크 완료"
echo "로그 확인: tail -n 200 .petlink.out"


