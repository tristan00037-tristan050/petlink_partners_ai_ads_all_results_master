#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts/migrations server/lib server/routes server/openapi server/adapters/billing

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export PAYMENT_WEBHOOK_SECRET="${PAYMENT_WEBHOOK_SECRET:-dev-webhook-secret}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ENABLE_CONSUMER_BILLING="${ENABLE_CONSUMER_BILLING:-false}"
export BILLING_ADAPTER="${BILLING_ADAPTER:-mock}"
export BILLING_MODE="${BILLING_MODE:-sandbox}"

echo "[1/8] DDL: Advertiser Billing 전용 스키마"

cat > scripts/migrations/20251112_ads_billing.sql <<'SQL'
-- 1) 광고비 청구서
CREATE TABLE IF NOT EXISTS ad_invoices(
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT UNIQUE NOT NULL,
  advertiser_id INTEGER NOT NULL,
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  status TEXT NOT NULL CHECK(status IN ('DUE','PAID','CANCELED')),
  meta JSONB,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_invoices_adv ON ad_invoices(advertiser_id);

-- 2) 결제수단(토큰/PAN 비보관)
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

-- 3) 광고비 결제
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
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_payments_invoice ON ad_payments(invoice_no);
CREATE INDEX IF NOT EXISTS idx_ad_payments_status  ON ad_payments(status);

-- 결제 상태 전이 가드
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='ad_payments_guard_transition') THEN
    CREATE FUNCTION ad_payments_guard_transition() RETURNS trigger AS $$
    DECLARE old TEXT := COALESCE(OLD.status,'PENDING'); DECLARE nw TEXT := NEW.status;
    BEGIN
      IF old=nw THEN RETURN NEW; END IF;
      IF old='PENDING'    AND nw IN('AUTHORIZED','FAILED') THEN RETURN NEW; END IF;
      IF old='AUTHORIZED' AND nw IN('CAPTURED','CANCELED','FAILED') THEN RETURN NEW; END IF;
      RAISE EXCEPTION 'invalid transition: % -> %', old, nw;
    END; $$ LANGUAGE plpgsql;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='ad_payments_guard_transition_tr') THEN
    CREATE TRIGGER ad_payments_guard_transition_tr
      BEFORE UPDATE ON ad_payments FOR EACH ROW
      EXECUTE PROCEDURE ad_payments_guard_transition();
  END IF;
END$$;

-- 4) 반복결제(선택)
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

-- 5) 은행입금(실시간 계좌이체/무통장 기록)
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

echo "[2/8] 라이브러리: 광고비 결제 도메인"

cat > server/lib/ads_billing.js <<'JS'
const db = require('./db');
const outbox = require('./outbox');

async function ensureInvoice(invoice_no, advertiser_id, amount, currency='KRW') {
  await db.q(
    `INSERT INTO ad_invoices(invoice_no, advertiser_id, amount, currency, status, created_at, updated_at)
     VALUES ($1,$2,$3,$4,'DUE',now(),now())
     ON CONFLICT (invoice_no) DO NOTHING`,
    [invoice_no, advertiser_id, amount, currency]
  );
}

async function ensurePayment(invoice_no, advertiser_id, amount, currency='KRW', provider='bootpay') {
  await db.q(
    `INSERT INTO ad_payments(invoice_no, advertiser_id, amount, currency, provider, status, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING',now(),now())
     ON CONFLICT DO NOTHING`,
    [invoice_no, advertiser_id, amount, currency, provider]
  );
}

async function bindMethod(invoice_no, method_id) {
  await db.q(`UPDATE ad_payments SET method_id=$2 WHERE invoice_no=$1`, [invoice_no, method_id]);
}

async function upsertProviderTxn(invoice_no, provider_txn_id) {
  if (!provider_txn_id) return;
  await db.q(
    `UPDATE ad_payments SET provider_txn_id = COALESCE(provider_txn_id, $2)
      WHERE invoice_no=$1`, [invoice_no, provider_txn_id]
  );
}

async function setStatus(invoice_no, status, meta={}) {
  return db.transaction(async (c) => {
    const r = await c.query(
      `UPDATE ad_payments
          SET status=$2, metadata = COALESCE(metadata,'{}')::jsonb || $3::jsonb, updated_at=now()
        WHERE invoice_no=$1
        RETURNING id, advertiser_id, amount`, [invoice_no, status, meta]
    );
    if (!r.rows.length) return null;
    const p = r.rows[0];
    if (status === 'CAPTURED') {
      await c.query(`UPDATE ad_invoices SET status='PAID', updated_at=now() WHERE invoice_no=$1`, [invoice_no]);
    } else if (status === 'CANCELED') {
      await c.query(`UPDATE ad_invoices SET status='CANCELED', updated_at=now() WHERE invoice_no=$1`, [invoice_no]);
    }
    await outbox.addEventTx(c, `AD_BILLING_${status}`, 'ad_payment', p.id, {
      invoice_no, advertiser_id: p.advertiser_id, amount: p.amount, meta
    });
    return p;
  });
}

module.exports = { ensureInvoice, ensurePayment, bindMethod, upsertProviderTxn, setStatus };
JS

echo "[3/8] 어댑터: mock / bootpay 골격"

cat > server/adapters/billing/index.js <<'JS'
const which = (process.env.BILLING_ADAPTER || 'mock').toLowerCase();
module.exports = which === 'bootpay' ? require('./bootpay') : require('./mock');
JS

cat > server/adapters/billing/mock.js <<'JS'
module.exports = {
  async registerMethod(/* advertiser_id, payload */){ return { ok:true, token: 'tok_mock_'+Date.now() }; },
  async authorize(/* invoice_no, amount, token */){ return { ok:true, provider_txn_id: 'auth_'+Date.now() }; },
  async capture(/* invoice_no, amount, token */){ return { ok:true, provider_txn_id: 'cap_'+Date.now() }; },
  async verify(/* provider_txn_id */){ return { ok:true, status:'CAPTURED' }; },
  verifyWebhook(rawBuf, req){
    const crypto = require('crypto');
    const secret = process.env.PAYMENT_WEBHOOK_SECRET || '';
    const ts = req.get('X-Webhook-Timestamp'); const sig=req.get('X-Webhook-Signature');
    if(!secret||!ts||!sig) return { ok:false, code:'SECRET_OR_HEADERS_EMPTY' };
    const now=Math.floor(Date.now()/1000); const t=parseInt(ts||'0',10);
    if(!t || Math.abs(now-t) > 300) return { ok:false, code:'TS_WINDOW_EXCEEDED' };
    const mac = crypto.createHmac('sha256', secret).update(String(t)).update('.').update(rawBuf).digest('hex');
    try{ const ok=crypto.timingSafeEqual(Buffer.from(mac,'hex'),Buffer.from(sig,'hex')); return ok?{ok:true}:{ok:false,code:'SIG_MISMATCH'}; }
    catch{ return { ok:false, code:'SIG_VERIFY_ERROR' }; }
  }
};
JS

cat > server/adapters/billing/bootpay.js <<'JS'
module.exports = {
  async registerMethod(){ return { ok:true, token:'tok_bootpay_placeholder' }; },
  async authorize(){ return { ok:true, provider_txn_id:'auth_bootpay_placeholder' }; },
  async capture(){ return { ok:true, provider_txn_id:'cap_bootpay_placeholder' }; },
  async verify(){ return { ok:true, status:'CAPTURED' }; },
  verifyWebhook(rawBuf, req){
    const crypto=require('crypto');
    const secret=process.env.PAYMENT_WEBHOOK_SECRET||''; const ts=req.get('X-Webhook-Timestamp'); const sig=req.get('X-Webhook-Signature');
    if(!secret||!ts||!sig) return { ok:false, code:'SECRET_OR_HEADERS_EMPTY' };
    const now=Math.floor(Date.now()/1000); const t=parseInt(ts||'0',10);
    if(!t || Math.abs(now-t) > 300) return { ok:false, code:'TS_WINDOW_EXCEEDED' };
    const mac=crypto.createHmac('sha256',secret).update(String(t)).update('.').update(rawBuf).digest('hex');
    try{ const ok=crypto.timingSafeEqual(Buffer.from(mac,'hex'),Buffer.from(sig,'hex')); return ok?{ok:true}:{ok:false,code:'SIG_MISMATCH'}; }
    catch{ return { ok:false, code:'SIG_VERIFY_ERROR' }; }
  }
};
JS

echo "[4/8] 라우트: /ads/billing/*"

cat > server/routes/ads_payment_methods.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const router=express.Router();

router.post('/', express.json(), async (req,res)=>{
  const { advertiser_id, pm_type, provider, token, brand, last4, set_default } = req.body||{};
  if(!advertiser_id || !pm_type || !provider || !token) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  await db.transaction(async(c)=>{
    await c.query(`INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default)
                   VALUES($1,$2,$3,$4,$5,$6,$7)
                   ON CONFLICT(advertiser_id,provider,token) DO NOTHING`,
                   [advertiser_id, pm_type, provider, token, brand||null, last4||null, !!set_default]);
    if(set_default){
      await c.query(`UPDATE payment_methods
                       SET is_default = (id = (SELECT id FROM payment_methods WHERE advertiser_id=$1 AND provider=$2 AND token=$3 LIMIT 1))
                     WHERE advertiser_id=$1`, [advertiser_id, provider, token]);
    }
  });
  res.json({ ok:true });
});

router.get('/', async (req,res)=>{
  const { advertiser_id } = req.query;
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_REQUIRED' });
  const { rows } = await db.q(`SELECT id,pm_type,provider,brand,last4,is_default,created_at FROM payment_methods WHERE advertiser_id=$1 ORDER BY id DESC`, [advertiser_id]);
  res.json({ ok:true, items: rows });
});

router.delete('/:id', async (req,res)=>{
  const id = parseInt(req.params.id,10);
  await db.q(`DELETE FROM payment_methods WHERE id=$1`, [id]);
  res.json({ ok:true });
});

router.post('/:id/default', async (req,res)=>{
  const id = parseInt(req.params.id,10);
  const { rows } = await db.q(`SELECT advertiser_id FROM payment_methods WHERE id=$1`, [id]);
  if(!rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  const adv = rows[0].advertiser_id;
  await db.transaction(async(c)=>{
    await c.query(`UPDATE payment_methods SET is_default=false WHERE advertiser_id=$1`, [adv]);
    await c.query(`UPDATE payment_methods SET is_default=true WHERE id=$1`, [id]);
  });
  res.json({ ok:true });
});

module.exports = router;
JS

cat > server/routes/ads_billing.js <<'JS'
const express=require('express'); const ads=require('../lib/ads_billing'); const db=require('../lib/db');
const adapter=require('../adapters/billing'); const router=express.Router();

function verifySignature(rawBuf, req){
  return adapter.verifyWebhook(rawBuf, req);
}

router.post('/invoices', express.json(), async (req,res)=>{
  const { invoice_no, advertiser_id, amount, currency } = req.body||{};
  if(!invoice_no || !advertiser_id) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  await ads.ensureInvoice(invoice_no, Number(advertiser_id), Number(amount||0), currency||'KRW');
  res.json({ ok:true });
});

router.post('/confirm', express.json(), async (req,res)=>{
  const { invoice_no, advertiser_id, amount, method_id, status='AUTHORIZED' } = req.body||{};
  if(!invoice_no || !advertiser_id) return res.status(400).json({ ok:false, code:'INVOICE_OR_ADVERTISER_REQUIRED' });
  const adv = Number(advertiser_id); const amt = Number(amount||0);
  await ads.ensureInvoice(invoice_no, adv, amt);
  await ads.ensurePayment(invoice_no, adv, amt);
  if(method_id){
    await ads.bindMethod(invoice_no, Number(method_id));
  }else{
    const r=await db.q(`SELECT id FROM payment_methods WHERE advertiser_id=$1 AND is_default=true LIMIT 1`, [adv]);
    if(r.rows.length) await ads.bindMethod(invoice_no, r.rows[0].id);
  }
  if((process.env.BILLING_MODE||'sandbox')==='sandbox'){
    await ads.setStatus(invoice_no, String(status).toUpperCase(), { source:'confirm' });
  }
  res.json({ ok:true, invoice_no, advertiser_id: adv, status: String(status).toUpperCase() });
});

router.post('/capture', express.json(), async (req,res)=>{
  const { invoice_no } = req.body||{};
  if(!invoice_no) return res.status(400).json({ ok:false, code:'INVOICE_REQUIRED' });
  await ads.setStatus(invoice_no, 'CAPTURED', { source:'capture' });
  res.json({ ok:true });
});

router.post('/webhook/pg', express.raw({ type:'application/json' }), async (req,res)=>{
  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from('');
  const v = verifySignature(raw, req);
  if(!v.ok) return res.status(401).json({ ok:false, code: v.code || 'INVALID_SIGNATURE' });
  let evt; try{ evt = JSON.parse(raw.toString('utf8')); }catch{ return res.status(400).json({ ok:false, code:'INVALID_JSON' }); }
  const invoice_no = evt.invoice_no || evt.order_id || null;
  const advertiser_id = Number(evt.advertiser_id || 0);
  const amount = Number(evt.amount || 0);
  const label = String(evt.event || evt.status || '').toUpperCase();
  const provider_txn_id = evt.txn_id || evt.receipt_id || evt.transactionId || null;
  if(!invoice_no || !advertiser_id || !label) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  await ads.ensureInvoice(invoice_no, advertiser_id, amount);
  await ads.ensurePayment(invoice_no, advertiser_id, amount);
  if(provider_txn_id) await ads.upsertProviderTxn(invoice_no, provider_txn_id);
  let status='PENDING';
  if(['AUTHORIZED','APPROVED'].includes(label)) status='AUTHORIZED';
  else if(['CAPTURED','PAID','DONE','CONFIRMED'].includes(label)) status='CAPTURED';
  else if(['CANCEL','CANCELED'].includes(label)) status='CANCELED';
  else if(['FAILED','FAIL','ERROR'].includes(label)) status='FAILED';
  await ads.setStatus(invoice_no, status, { source:'webhook', label, provider_txn_id });
  res.json({ ok:true });
});

module.exports = router;
JS

cat > server/routes/ads_billing_admin.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const admin=require('../mw/admin'); const router=express.Router();

router.use(admin.requireAdmin);

router.post('/deposits/import', express.json(), async (req,res)=>{
  const items = Array.isArray(req.body) ? req.body : [];
  let n=0;
  await db.transaction(async(c)=>{
    for(const it of items){
      await c.query(`INSERT INTO bank_deposits(advertiser_id,invoice_no,amount,deposit_time,bank_code,account_mask,ref_no,memo,created_by)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [it.advertiser_id||null, it.invoice_no||null, Number(it.amount||0), it.deposit_time||new Date().toISOString(),
         it.bank_code||null, it.account_mask||null, it.ref_no||null, it.memo||null, it.created_by||'admin']);
      n++;
      if(it.invoice_no && it.amount!=null){
        await c.query(`UPDATE ad_invoices SET status='PAID', updated_at=now() WHERE invoice_no=$1 AND amount=$2`, [it.invoice_no, Number(it.amount||0)]);
      }
    }
  });
  res.json({ ok:true, imported: n });
});

router.get('/deposits', async (req,res)=>{
  const { advertiser_id, invoice_no, from, to } = req.query;
  const params=[]; const where=[];
  if(advertiser_id){ params.push(Number(advertiser_id)); where.push(`advertiser_id=$${params.length}`); }
  if(invoice_no){ params.push(String(invoice_no)); where.push(`invoice_no=$${params.length}`); }
  if(from){ params.push(String(from)); where.push(`deposit_time>=to_timestamp($${params.length})`); }
  if(to){ params.push(String(to)); where.push(`deposit_time<=to_timestamp($${params.length})`); }
  const sql = `SELECT id,advertiser_id,invoice_no,amount,deposit_time,bank_code,ref_no,memo,created_by
               FROM bank_deposits ${where.length?'WHERE '+where.join(' AND '):''} ORDER BY id DESC LIMIT 200`;
  const { rows } = await db.q(sql, params);
  res.json({ ok:true, items: rows });
});

module.exports = router;
JS

echo "[5/8] OpenAPI 문서"

cat > server/openapi/ads_billing.yaml <<'YAML'
openapi: 3.0.3
info: { title: Advertiser Billing API, version: "r5.2B" }
servers: [ { url: http://localhost:5902 } ]
paths:
  /ads/billing/payment-methods:
    get:
      summary: List payment methods for advertiser
      parameters: [ { in: query, name: advertiser_id, required: true, schema: { type: integer } } ]
      responses: { '200': { description: OK } }
    post:
      summary: Register payment method token
      requestBody:
        required: true
        content: { application/json: { schema: { type: object, required: [advertiser_id, pm_type, provider, token],
          properties: { advertiser_id:{type:integer}, pm_type:{type:string,enum:[CARD,NAVERPAY,KAKAOPAY,BANK]},
                      provider:{type:string}, token:{type:string}, brand:{type:string}, last4:{type:string}, set_default:{type:boolean} } } } }
      responses: { '200': { description: OK } }
  /ads/billing/payment-methods/{id}:
    delete: { summary: Delete method, responses: { '200': { description: OK } } }
  /ads/billing/payment-methods/{id}/default:
    post: { summary: Set default method, responses: { '200': { description: OK } } }
  /ads/billing/invoices:
    post:
      summary: Create ad invoice (DUE)
      requestBody:
        required: true
        content: { application/json: { schema: { type: object, required: [invoice_no, advertiser_id, amount],
          properties: { invoice_no:{type:string}, advertiser_id:{type:integer}, amount:{type:integer}, currency:{type:string} } } } }
      responses: { '200': { description: OK } }
  /ads/billing/confirm:
    post:
      summary: Authorize advertiser billing
      requestBody:
        required: true
        content: { application/json: { schema: { type: object, required: [invoice_no, advertiser_id],
          properties: { invoice_no:{type:string}, advertiser_id:{type:integer}, amount:{type:integer},
                       method_id:{type:integer,nullable:true}, status:{type:string,enum:[AUTHORIZED,CAPTURED,CANCELED]} } } } }
      responses: { '200': { description: OK } }
  /ads/billing/capture:
    post:
      summary: Capture advertiser billing
      requestBody: { required: true, content: { application/json: { schema: { type: object, required: [invoice_no], properties: { invoice_no:{type:string} } } } } }
      responses: { '200': { description: OK } }
  /ads/billing/webhook/pg:
    post:
      summary: PG webhook (HMAC)
      responses: { '200': { description: OK }, '401': { description: Invalid signature }, '400': { description: Invalid JSON } }
YAML

cat > server/openapi/ads_billing.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Advertiser Billing API</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css"/>
<div id="swagger"></div>
<script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
<script>window.ui = SwaggerUIBundle({ url: '/openapi_ads_billing.yaml', dom_id: '#swagger' });</script>
HTML

echo "[6/8] app.js 패치: raw→json 순서 보장, 라우트/문서 장착"

# webhook 원문 보존 (express.raw가 express.json보다 먼저)
if ! grep -q "/ads/billing/webhook/pg" server/app.js; then
  # express.json() 이전에 추가
  sed -i.bak '/app.use(express.json/ i\
app.use("/ads/billing/webhook/pg", require("express").raw({ type: "application/json" }));\
' server/app.js 2>/dev/null || true
  rm -f server/app.js.bak 2>/dev/null || true
fi

# 라우트/문서 등록
if ! grep -q "routes/ads_billing" server/app.js; then
  # express.json() 이후에 추가
  sed -i.bak '/app.use(express.json/ a\
app.use("/ads/billing/payment-methods", require("./routes/ads_payment_methods"));\
app.use("/ads/billing", require("./routes/ads_billing"));\
app.use("/admin/ads/billing", require("./mw/admin").requireAdmin, require("./routes/ads_billing_admin"));\
app.get("/openapi_ads_billing.yaml", (req, res) => res.sendFile(require("path").join(__dirname, "openapi", "ads_billing.yaml")));\
app.get("/docs-ads-billing", (req, res) => res.sendFile(require("path").join(__dirname, "openapi", "ads_billing.html")));\
' server/app.js 2>/dev/null || true
  rm -f server/app.js.bak 2>/dev/null || true
fi

# 소비자 결제 라우트 비활성 (ENABLE_CONSUMER_BILLING=false일 때)
if [ "${ENABLE_CONSUMER_BILLING}" = "false" ]; then
  sed -i.bak 's|^app.use("/billing",|// app.use("/billing",|g' server/app.js 2>/dev/null || true
  sed -i.bak 's|^app.get("/openapi_r51.yaml"|// app.get("/openapi_r51.yaml"|g' server/app.js 2>/dev/null || true
  sed -i.bak 's|^app.get("/docs-payments"|// app.get("/docs-payments"|g' server/app.js 2>/dev/null || true
  rm -f server/app.js.bak 2>/dev/null || true
fi

echo "[7/8] 마이그레이션 실행"
if [ -f scripts/run_sql.js ]; then
  node scripts/run_sql.js scripts/migrations/20251112_ads_billing.sql || psql "$DATABASE_URL" -f scripts/migrations/20251112_ads_billing.sql
else
  psql "$DATABASE_URL" -f scripts/migrations/20251112_ads_billing.sql
fi

echo "[8/8] [ads-billing overlay] ready"

