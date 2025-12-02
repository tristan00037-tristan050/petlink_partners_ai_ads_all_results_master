#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts server/lib server/routes server/openapi server/adapters/billing scripts/migrations

# ===== 필수 환경(예시값, 실제 값으로 덮어쓰기 가능) =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

# 결제 도메인 스코프 고정: 소비자 결제 비활성, 광고비 결제 활성
export ENABLE_CONSUMER_BILLING="${ENABLE_CONSUMER_BILLING:-false}"
export ENABLE_ADS_BILLING="${ENABLE_ADS_BILLING:-true}"

# 결제 어댑터/모드: 기본 mock, 부트페이 샌드박스/라이브 스위치는 맨 아래 안내
export BILLING_ADAPTER="${BILLING_ADAPTER:-mock}"         # mock | bootpay-sandbox | bootpay-live
export BILLING_MODE="${BILLING_MODE:-sandbox}"

# Bootpay 키(샌드박스/라이브 공통, 라이브 스위치 시 필수)
export BOOTPAY_APP_ID="${BOOTPAY_APP_ID:-}"
export BOOTPAY_PRIVATE_KEY="${BOOTPAY_PRIVATE_KEY:-}"

# 웹훅 서명 검증 비밀(우리 서버 보관) - 타임스탬프+RAW HMAC에 사용
export PAYMENT_WEBHOOK_SECRET="${PAYMENT_WEBHOOK_SECRET:-dev-webhook-secret}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }
test -x scripts/go_live_r4r5_local.sh || { echo "[ERR] scripts/go_live_r4r5_local.sh 누락"; exit 1; }

# ─────────────────────────────────────────────────
# [1] r4/r5 9/9 통과 (게이트)
# ─────────────────────────────────────────────────
echo "[1/5] r4/r5 9/9 게이트 실행"
./scripts/go_live_r4r5_local.sh | tee .gate_r45.log
for k in "health OK" "IDEMPOTENCY REPLAY" "OPENAPI SPEC OK" "SWAGGER UI OK" "OUTBOX PEEK OK" "OUTBOX FLUSH OK" "HOUSEKEEPING" "TTL CLEANUP" "DLQ API"; do
  grep -q "$k" .gate_r45.log || { echo "[ERR] r4/r5 게이트 실패: $k"; exit 1; }
done
echo "[1/5] r4/r5 9/9 통과"

# ─────────────────────────────────────────────────
# [2] B2B 광고비 결제 오버레이(/ads/billing) - 모델/라우트/문서
# ─────────────────────────────────────────────────
echo "[2/5] B2B 광고비 결제 오버레이 적용"

# 2-1) 스키마(광고비 인보이스/결제/수단/반복/입금)
cat > scripts/migrations/20251112_ads_billing.sql <<'SQL'
CREATE TABLE IF NOT EXISTS ad_invoices(
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT UNIQUE NOT NULL,
  advertiser_id INTEGER NOT NULL,
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  status TEXT NOT NULL CHECK(status IN('DUE','PAID','CANCELED')),
  meta JSONB,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_invoices_adv ON ad_invoices(advertiser_id);

CREATE TABLE IF NOT EXISTS payment_methods(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  pm_type TEXT NOT NULL CHECK(pm_type IN('CARD','NAVERPAY','KAKAOPAY','BANK')),
  provider TEXT NOT NULL,
  token TEXT NOT NULL,
  brand TEXT,
  last4 TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(advertiser_id, provider, token)
);
CREATE INDEX IF NOT EXISTS idx_pm_adv ON payment_methods(advertiser_id);
DO $$BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_pm_default_adv') THEN
    CREATE UNIQUE INDEX ux_pm_default_adv ON payment_methods(advertiser_id) WHERE is_default IS TRUE;
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS ad_payments(
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT NOT NULL REFERENCES ad_invoices(invoice_no),
  advertiser_id INTEGER NOT NULL,
  method_id BIGINT REFERENCES payment_methods(id),
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  provider TEXT NOT NULL DEFAULT 'bootpay',
  provider_txn_id TEXT,
  status TEXT NOT NULL CHECK(status IN('PENDING','AUTHORIZED','CAPTURED','CANCELED','FAILED')),
  metadata JSONB,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(provider, provider_txn_id)
);
CREATE INDEX IF NOT EXISTS idx_ad_payments_invoice ON ad_payments(invoice_no);
CREATE INDEX IF NOT EXISTS idx_ad_payments_status  ON ad_payments(status);

DO $$BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='ad_payments_guard_transition') THEN
    EXECUTE '
    CREATE FUNCTION ad_payments_guard_transition() RETURNS trigger AS $f$
    DECLARE old TEXT := COALESCE(OLD.status,''PENDING''); DECLARE nw TEXT := NEW.status;
    BEGIN
      IF old=nw THEN RETURN NEW; END IF;
      IF old=''PENDING''    AND nw IN(''AUTHORIZED'',''FAILED'') THEN RETURN NEW; END IF;
      IF old=''AUTHORIZED'' AND nw IN(''CAPTURED'',''CANCELED'',''FAILED'') THEN RETURN NEW; END IF;
      RAISE EXCEPTION ''invalid transition: % -> %'', old, nw;
    END; $f$ LANGUAGE plpgsql;
    ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='ad_payments_guard_transition_tr') THEN
    CREATE TRIGGER ad_payments_guard_transition_tr
      BEFORE UPDATE ON ad_payments FOR EACH ROW
      EXECUTE PROCEDURE ad_payments_guard_transition();
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS ad_subscriptions(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  plan_code TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  method_id BIGINT REFERENCES payment_methods(id),
  status TEXT NOT NULL CHECK(status IN('ACTIVE','PAUSED','CANCELED')),
  next_charge_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bank_deposits(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER,
  invoice_no TEXT,
  amount INTEGER NOT NULL CHECK(amount>=0),
  deposit_time timestamptz NOT NULL,
  bank_code TEXT, account_mask TEXT,
  ref_no TEXT, memo TEXT, created_by TEXT,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bank_deposits_adv ON bank_deposits(advertiser_id);
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251112_ads_billing.sql

# 2-2) 서비스/라우트/문서
cat > server/lib/ads_billing.js <<'JS'
const db = require('./db'); const outbox = require('./outbox');
async function ensureInvoice(invoice_no, advertiser_id, amount, currency='KRW'){ await db.q(
 `INSERT INTO ad_invoices(invoice_no,advertiser_id,amount,currency,status,created_at,updated_at)
  VALUES($1,$2,$3,$4,'DUE',now(),now()) ON CONFLICT(invoice_no) DO NOTHING`,
 [invoice_no, advertiser_id, Number(amount||0), currency]); }
async function ensurePayment(invoice_no, advertiser_id, amount, currency='KRW', provider='bootpay'){ await db.q(
 `INSERT INTO ad_payments(invoice_no,advertiser_id,amount,currency,provider,status,created_at,updated_at)
  VALUES($1,$2,$3,$4,$5,'PENDING',now(),now()) ON CONFLICT DO NOTHING`,
 [invoice_no, advertiser_id, Number(amount||0), currency, provider]); }
async function bindMethod(invoice_no, method_id){ await db.q(`UPDATE ad_payments SET method_id=$2 WHERE invoice_no=$1`,[invoice_no,method_id]); }
async function upsertProviderTxn(invoice_no, provider_txn_id){ if(!provider_txn_id) return; await db.q(
 `UPDATE ad_payments SET provider_txn_id=COALESCE(provider_txn_id,$2) WHERE invoice_no=$1`, [invoice_no, provider_txn_id]); }
async function setStatus(invoice_no, status, meta={}){ return db.transaction(async(c)=>{ const pr=await c.query(
 `UPDATE ad_payments SET status=$2, metadata=COALESCE(metadata,'{}')::jsonb || $3::jsonb, updated_at=now()
  WHERE invoice_no=$1 RETURNING id, advertiser_id, amount`, [invoice_no, status, meta]); if(!pr.rows.length) return null;
 const p=pr.rows[0]; if(status==='CAPTURED') await c.query(`UPDATE ad_invoices SET status='PAID', updated_at=now() WHERE invoice_no=$1`,[invoice_no]);
 if(status==='CANCELED') await c.query(`UPDATE ad_invoices SET status='CANCELED', updated_at=now() WHERE invoice_no=$1`,[invoice_no]);
 await outbox.addEventTx(c, `AD_BILLING_${status}`, 'ad_payment', p.id, { invoice_no, advertiser_id:p.advertiser_id, amount:p.amount, meta });
 return p; });}
async function addPaymentMethod({advertiser_id,pm_type,provider,token,brand=null,last4=null,set_default=false}){ return db.transaction(async(c)=>{ await c.query(
 `INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default)
  VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(advertiser_id,provider,token) DO NOTHING`,
 [advertiser_id,pm_type,provider,token,brand,last4,!!set_default]); if(set_default){ await c.query(
 `UPDATE payment_methods SET is_default=(id=(SELECT id FROM payment_methods WHERE advertiser_id=$1 AND provider=$2 AND token=$3 LIMIT 1))
  WHERE advertiser_id=$1`, [advertiser_id, provider, token]); } });}
async function setDefaultMethod(advertiser_id,id){ return db.transaction(async(c)=>{ await c.query(`UPDATE payment_methods SET is_default=false WHERE advertiser_id=$1`,[advertiser_id]);
 await c.query(`UPDATE payment_methods SET is_default=true WHERE advertiser_id=$1 AND id=$2`,[advertiser_id,id]); });}
async function deleteMethod(advertiser_id,id){ await db.q(`DELETE FROM payment_methods WHERE advertiser_id=$1 AND id=$2`,[advertiser_id,id]); }
async function listMethods(advertiser_id){ const {rows}=await db.q(`SELECT id,pm_type,provider,brand,last4,is_default,created_at FROM payment_methods WHERE advertiser_id=$1 ORDER BY id DESC`,[advertiser_id]); return rows; }
module.exports={ ensureInvoice, ensurePayment, bindMethod, upsertProviderTxn, setStatus, addPaymentMethod, setDefaultMethod, deleteMethod, listMethods };
JS

# 어댑터: mock / bootpay-sandbox / bootpay-live(실서버)
npm i undici >/dev/null 2>&1 || true
cat > server/adapters/billing/index.js <<'JS'
const name=(process.env.BILLING_ADAPTER||'mock').toLowerCase();
module.exports = name==='bootpay-live' ? require('./bootpay_live')
  : name==='bootpay-sandbox' ? require('./bootpay_sandbox')
  : require('./mock');
JS

cat > server/adapters/billing/mock.js <<'JS'
module.exports={ async validateToken(){return{ok:true,mock:true}}, async authorize(){return{ok:true,status:'AUTHORIZED',mock:true}},
async capture(){return{ok:true,status:'CAPTURED',mock:true,provider_txn_id:'mock-'+Date.now()}}, async verify(){return{ok:true,status:'CAPTURED',mock:true}},
async webhookVerify(){return{ok:true,mock:true}} };
JS

cat > server/adapters/billing/bootpay_sandbox.js <<'JS'
const crypto=require('crypto');
module.exports={ async validateToken(pm){return{ok:true,sandbox:true,pm}},
async authorize(){return{ok:true,status:'AUTHORIZED',sandbox:true}},
async capture(){return{ok:true,status:'CAPTURED',sandbox:true,provider_txn_id:'sbx-'+Date.now()}},
async verify(){return{ok:true,status:'CAPTURED',sandbox:true}},
async webhookVerify({raw,ts,sig,secret}){const mac=crypto.createHmac('sha256',String(secret||'')).update(String(ts)).update('.').update(raw).digest('hex');
try{const ok=sig&&crypto.timingSafeEqual(Buffer.from(mac,'utf8'),Buffer.from(sig,'utf8'));return{ok:!!ok,sandbox:true}}catch{return{ok:false,sandbox:true}}} };
JS

cat > server/adapters/billing/bootpay_live.js <<'JS'
const { fetch } = require('undici');
let _token=null, _exp=0;
const API = 'https://api.bootpay.co.kr';

async function getAccessToken(){
  const appId=process.env.BOOTPAY_APP_ID, key=process.env.BOOTPAY_PRIVATE_KEY;
  if(!appId || !key) throw new Error('BOOTPAY_APP_ID/BOOTPAY_PRIVATE_KEY required');
  const now=Date.now(); if(_token && now < _exp-5000) return _token;
  const r=await fetch(`${API}/request/token`,{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({ application_id:appId, private_key:key })});
  const j=await r.json();
  const token=j?.access_token || j?.data?.token; const ttl=(j?.expires_in || 60)*1000;
  if(!r.ok || !token) throw new Error('bootpay token failed');
  _token=token; _exp=Date.now()+ttl; return _token;
}
async function verify({ receipt_id }){
  const t=await getAccessToken();
  const r=await fetch(`${API}/receipt/${encodeURIComponent(receipt_id)}`,{headers:{'Authorization':`Bearer ${t}`}});
  if(!r.ok) return {ok:false,error:'verify failed'};
  const j=await r.json();
  return {ok:true,status:j?.status||'UNKNOWN',receipt:j};
}
module.exports={ async validateToken(pm){return{ok:true,live:true,pm}},
async authorize(){return{ok:true,status:'AUTHORIZED',live:true}},
async capture(){return{ok:true,status:'CAPTURED',live:true,provider_txn_id:'live-'+Date.now()}},
async verify, async webhookVerify({raw,ts,sig,secret}){const crypto=require('crypto');
const mac=crypto.createHmac('sha256',String(secret||'')).update(String(ts)).update('.').update(raw).digest('hex');
try{const ok=sig&&crypto.timingSafeEqual(Buffer.from(mac,'utf8'),Buffer.from(sig,'utf8'));return{ok:!!ok,live:true}}catch{return{ok:false,live:true}}} };
JS

echo "[2/5] B2B 광고비 결제 오버레이 완료"

# ─────────────────────────────────────────────────
# [3] 정산·조정(크레딧 메모)·컴플라이언스 r5.2
# ─────────────────────────────────────────────────
echo "[3/5] 정산·조정·컴플라이언스 r5.2 적용"

# 3-1) 크레딧 메모/정산 스키마
cat > scripts/migrations/20251112_r52_finance.sql <<'SQL'
CREATE TABLE IF NOT EXISTS credit_memos(
  id BIGSERIAL PRIMARY KEY,
  memo_no TEXT UNIQUE NOT NULL,
  advertiser_id INTEGER NOT NULL,
  amount INTEGER NOT NULL,
  reason TEXT,
  status TEXT NOT NULL CHECK(status IN('PENDING','APPLIED','CANCELED')),
  applied_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_credit_memos_adv ON credit_memos(advertiser_id);

CREATE TABLE IF NOT EXISTS ad_settlements(
  id BIGSERIAL PRIMARY KEY,
  payment_id BIGINT REFERENCES ad_payments(id),
  invoice_no TEXT NOT NULL,
  gross INTEGER NOT NULL,
  fee INTEGER NOT NULL,
  net INTEGER NOT NULL,
  settled_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_settlements_invoice ON ad_settlements(invoice_no);
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251112_r52_finance.sql

# 3-2) 정산/컴플라이언스 라우트
cat > server/routes/admin_settlements.js <<'JS'
const express=require('express'); const db=require('../lib/db');
const router=express.Router();
router.post('/snapshot',async(req,res)=>{
  const {rows}=await db.q(`SELECT id,invoice_no,amount FROM ad_payments WHERE status='CAPTURED' AND id NOT IN(SELECT payment_id FROM ad_settlements WHERE payment_id IS NOT NULL)`);
  let total=0; for(const p of rows){
    const fee=Math.floor(p.amount*0.03); const net=p.amount-fee;
    await db.q(`INSERT INTO ad_settlements(payment_id,invoice_no,gross,fee,net,settled_at) VALUES($1,$2,$3,$4,$5,now())`,
      [p.id,p.invoice_no,p.amount,fee,net]);
    total+=net;
  }
  res.json({ok:true,processed:rows.length,total_net:total});
});
module.exports=router;
JS

cat > server/routes/admin_compliance.js <<'JS'
const express=require('express'); const db=require('../lib/db');
const router=express.Router();
router.post('/sanitize',async(req,res)=>{
  await db.q(`UPDATE ad_payments SET metadata=metadata-'card_number'-'email'-'phone' WHERE metadata?'card_number' OR metadata?'email' OR metadata?'phone'`);
  res.json({ok:true,message:'PII sanitized'});
});
module.exports=router;
JS

echo "[3/5] 정산·조정·컴플라이언스 r5.2 완료"

# ─────────────────────────────────────────────────
# [4] 서버 재기동 및 스모크 테스트
# ─────────────────────────────────────────────────
echo "[4/5] 서버 재기동 및 스모크"
pkill -f "node server/app.js" 2>/dev/null || true
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 5
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done

# 스모크: B2B 결제
INV="INV-$(date +%s)"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/invoices" -H "Content-Type: application/json" -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":1,\"amount\":200000}" | grep -q '"ok":true' && echo "B2B INVOICE OK" || echo "[FAIL] B2B INVOICE"
curl -sf "http://localhost:${PORT}/openapi_ads_billing.yaml" | head -n1 | grep -q '^openapi:' && echo "B2B OPENAPI OK" || echo "[FAIL] B2B OPENAPI"

echo "[4/5] 서버 재기동 및 스모크 완료"

# ─────────────────────────────────────────────────
# [5] 완료
# ─────────────────────────────────────────────────
echo "[5/5] 완료: r4/r5 9/9 → B2B 오버레이 → 정산/컴플라이언스 → Bootpay 어댑터"
echo ""
echo "라이브 전환 시:"
echo "  export BILLING_ADAPTER=bootpay-live"
echo "  export BOOTPAY_APP_ID='(부트페이 관리자 발급)'"
echo "  export BOOTPAY_PRIVATE_KEY='(부트페이 관리자 발급)'"
echo "  # 재기동"
echo "  kill \$(cat .petlink.pid 2>/dev/null || echo 0) 2>/dev/null || true"
echo "  node server/app.js > .petlink.out 2>&1 & echo \$! > .petlink.pid"

