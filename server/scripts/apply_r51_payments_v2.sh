#!/usr/bin/env bash
set -euo pipefail
echo "[r5.1v2] apply start"

mkdir -p scripts/migrations server/lib server/routes server/openapi

# A) 마이그레이션(상태 전이 가드, provider+txn 유니크, 금액 제약)
cat > scripts/migrations/20251112_r51_v2.sql <<'SQL'
-- 상태 전이 가드 트리거
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='payments_guard_transition') THEN
    CREATE OR REPLACE FUNCTION payments_guard_transition() RETURNS trigger AS $f$
    DECLARE old TEXT := COALESCE(OLD.status,'PENDING');
    DECLARE nw  TEXT := NEW.status;
    BEGIN
      IF old = nw THEN RETURN NEW; END IF;
      IF old = 'PENDING'    AND nw IN ('AUTHORIZED','FAILED') THEN RETURN NEW; END IF;
      IF old = 'AUTHORIZED' AND nw IN ('CAPTURED','CANCELED','FAILED') THEN RETURN NEW; END IF;
      IF old IN ('CAPTURED','CANCELED','FAILED') THEN
        RAISE EXCEPTION 'invalid transition: % -> %', old, nw;
      END IF;
      RAISE EXCEPTION 'invalid transition: % -> %', old, nw;
    END;
    $f$ LANGUAGE plpgsql;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='payments_guard_transition_tr') THEN
    CREATE TRIGGER payments_guard_transition_tr
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE PROCEDURE payments_guard_transition();
  END IF;
END$$;

-- 기존 provider_txn_id UNIQUE 제약이 있다면 제거(컬럼 단일 유니크 → 부분 유니크로 전환)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='payments'::regclass AND conname='payments_provider_txn_id_key'
  ) THEN
    ALTER TABLE payments DROP CONSTRAINT payments_provider_txn_id_key;
  END IF;
END$$;

-- provider + provider_txn_id 부분 유니크(널 허용)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname='ux_payments_provider_txn_nullable'
  ) THEN
    CREATE UNIQUE INDEX ux_payments_provider_txn_nullable
      ON payments(provider, provider_txn_id)
      WHERE provider_txn_id IS NOT NULL;
  END IF;
END$$;

-- 금액 음수 방지
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
      WHERE conrelid='payments'::regclass AND conname='payments_amount_nonneg'
  ) THEN
    ALTER TABLE payments
      ADD CONSTRAINT payments_amount_nonneg CHECK (amount >= 0);
  END IF;
END$$;
SQL

# B) outbox에 트랜잭션 API 추가(addEventTx)
cat > server/lib/outbox.js <<'JS'
const fs = require('fs');
const path = require('path');
const express = require('express');
const db = require('./db');

const MAX_ATTEMPTS = parseInt(process.env.OUTBOX_MAX_ATTEMPTS || '12', 10);
const BASE_BACKOFF_MS = parseInt(process.env.OUTBOX_BACKOFF_BASE_MS || '500', 10);
const MAX_BACKOFF_MS = parseInt(process.env.OUTBOX_BACKOFF_MAX_MS  || String(60*1000), 10);
const FAIL_EVENT = process.env.OUTBOX_FAIL_EVENT || '';

function computeBackoff(attempts){
  const a = Math.max(1, attempts);
  return Math.min(BASE_BACKOFF_MS * Math.pow(2, a - 1), MAX_BACKOFF_MS);
}

async function addEvent(event_type, aggregate_type, aggregate_id, payload = {}, headers = {}) {
  await db.q(
    `INSERT INTO outbox(aggregate_type, aggregate_id, event_type, payload, headers, status, attempts, available_at, created_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING',0, now(), now())`,
    [aggregate_type, aggregate_id, event_type, payload, headers]
  );
}

/** 트랜잭션 내 outbox 적재 (client가 있으면 client.query 사용) */
async function addEventTx(client, event_type, aggregate_type, aggregate_id, payload = {}, headers = {}) {
  const q = client && typeof client.query === 'function'
    ? (sql, params) => client.query(sql, params)
    : (sql, params) => db.q(sql, params);
  await q(
    `INSERT INTO outbox(aggregate_type, aggregate_id, event_type, payload, headers, status, attempts, available_at, created_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING',0, now(), now())`,
    [aggregate_type, aggregate_id, event_type, payload, headers]
  );
}

async function fetchBatch(limit = 50) {
  const { rows } = await db.q(
    `SELECT id, event_type, aggregate_type, aggregate_id, payload
       FROM outbox
      WHERE status='PENDING' AND available_at<=now()
      ORDER BY id ASC
      LIMIT $1`, [limit]
  );
  return rows;
}

async function markSent(id){
  await db.q(`UPDATE outbox SET status='SENT', updated_at=now(), last_error=NULL WHERE id=$1`, [id]);
}

async function markRetry(ev, errMsg){
  const u1 = await db.q(`UPDATE outbox SET attempts=attempts+1, updated_at=now(), last_error=$2 WHERE id=$1 RETURNING attempts`, [ev.id, String(errMsg).slice(0, 500)]);
  const att = u1.rows[0].attempts;
  if (att >= MAX_ATTEMPTS) {
    await db.q(
      `INSERT INTO outbox_dlq(src_outbox_id, aggregate_type, aggregate_id, event_type, payload, headers, failure)
       SELECT id, aggregate_type, aggregate_id, event_type, payload, headers, $2 FROM outbox WHERE id=$1`,
      [ev.id, String(errMsg).slice(0, 1000)]
    );
    await db.q(`UPDATE outbox SET status='DEAD', updated_at=now() WHERE id=$1`, [ev.id]);
    return { dead: true, attempts: att };
  }
  const backoffMs = computeBackoff(att);
  const nextAt = new Date(Date.now() + backoffMs).toISOString();
  await db.q(`UPDATE outbox SET available_at=$2 WHERE id=$1`, [ev.id, nextAt]);
  return { dead: false, attempts: att, backoffMs };
}

function startWorker({ intervalMs = 2000, logFile = path.join(process.cwd(), '.outbox.log') } = {}) {
  setInterval(async ()=> {
    try {
      const batch = await fetchBatch(50);
      for (const ev of batch) {
        try {
          if (FAIL_EVENT && ev.event_type === FAIL_EVENT) throw new Error('simulated_failure');
          fs.appendFileSync(logFile, JSON.stringify({ ts:new Date().toISOString(), ...ev }) + '\n');
          await markSent(ev.id);
        } catch(e){
          await markRetry(ev, e && e.message ? e.message : String(e));
        }
      }
    } catch(_) {}
  }, intervalMs);
}

function adminRouter(){
  const r = express.Router();
  r.get('/peek', async (req,res)=>{
    const { rows } = await db.q(`SELECT status, count(*)::int AS count FROM outbox GROUP BY status ORDER BY status`);
    const next = await db.q(`SELECT min(available_at) AS next_pending FROM outbox WHERE status='PENDING'`);
    res.json({ stats: rows, next_pending: next.rows[0] && next.rows[0].next_pending });
  });
  r.get('/dlq', async (req,res)=>{
    const limit = Math.min(parseInt(req.query.limit || '10',10), 100);
    const { rows } = await db.q(`SELECT id, src_outbox_id, event_type, aggregate_type, aggregate_id, failed_at FROM outbox_dlq ORDER BY id DESC LIMIT $1`, [limit]);
    res.json({ items: rows });
  });
  r.post('/requeue/:id', async (req,res)=>{
    const id = parseInt(req.params.id,10);
    const q = await db.q(`SELECT * FROM outbox_dlq WHERE id=$1`, [id]);
    if (!q.rows.length) return res.status(404).json({ code:'DLQ_NOT_FOUND' });
    const x = q.rows[0];
    await db.q(
      `INSERT INTO outbox(aggregate_type, aggregate_id, event_type, payload, headers, status, attempts, available_at, created_at)
       VALUES ($1,$2,$3,$4,$5,'PENDING',0, now(), now())`,
      [x.aggregate_type, x.aggregate_id, x.event_type, x.payload, x.headers]
    );
    await db.q(`DELETE FROM outbox_dlq WHERE id=$1`, [id]);
    res.json({ requeued: id });
  });
  return r;
}

module.exports = { addEvent, addEventTx, startWorker, adminRouter };
JS

# C) payments 라이브러리(트랜잭션 원자성)
cat > server/lib/payments.js <<'JS'
const db = require('./db');
const outbox = require('./outbox');

async function ensureOrder(order_id, store_id, amount, currency='KRW', provider='bootpay') {
  await db.q(
    `INSERT INTO payments(order_id, store_id, amount, currency, provider, status, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING', now(), now())
     ON CONFLICT (order_id) DO NOTHING`,
    [order_id, store_id, Number(amount||0), currency, provider]
  );
}

async function upsertProviderTxn(order_id, provider_txn_id) {
  if (!provider_txn_id) return;
  await db.q(
    `UPDATE payments
        SET provider_txn_id = COALESCE(provider_txn_id, $2)
      WHERE order_id = $1`,
    [order_id, provider_txn_id]
  );
}

/** 상태 변경 + outbox 이벤트를 하나의 트랜잭션으로 기록 */
async function setStatus(order_id, status, meta = {}) {
  return db.transaction(async (client) => {
    const r = await client.query(
      `UPDATE payments
          SET status=$2,
              metadata = COALESCE(metadata,'{}')::jsonb || $3::jsonb,
              updated_at=now()
        WHERE order_id=$1
        RETURNING id, store_id, amount`,
      [order_id, status, meta]
    );
    if (!r.rows.length) return null;
    const p = r.rows[0];
    await outbox.addEventTx(client, `PAYMENT_${status}`, 'payment', p.id, {
      order_id, store_id: p.store_id, amount: p.amount, meta
    });
    return p;
  });
}

module.exports = { ensureOrder, upsertProviderTxn, setStatus };
JS

# D) 라우트(서명: HMAC(ts + '.' + body), 리플레이 방지, raw 우선)
cat > server/routes/payments.js <<'JS'
const express = require('express');
const crypto = require('crypto');
const payments = require('../lib/payments');

const router = express.Router();

function verifySignature(rawBuf, sig, ts) {
  const secret = process.env.PAYMENT_WEBHOOK_SECRET || '';
  if (!secret) return { ok:false, code:'SECRET_EMPTY' };
  const now = Math.floor(Date.now()/1000);
  const t = parseInt(ts || '0', 10);
  if (!t || Math.abs(now - t) > 300) return { ok:false, code:'TS_WINDOW_EXCEEDED' }; // ±5분
  const mac = crypto.createHmac('sha256', secret)
                    .update(String(t)).update('.').update(rawBuf)
                    .digest('hex');
  try {
    const ok = crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(sig || '', 'utf8'));
    return ok ? { ok:true } : { ok:false, code:'SIG_MISMATCH' };
  } catch { return { ok:false, code:'SIG_VERIFY_ERROR' }; }
}

// confirm: 멱등(order_id 유니크) + 수치 유효성
router.post('/confirm', express.json(), async (req, res) => {
  const { order_id, provider_txn_id, amount, store_id, status } = req.body || {};
  if (!order_id) return res.status(400).json({ ok:false, code:'ORDER_ID_REQUIRED' });
  if (amount != null && Number.isNaN(Number(amount))) {
    return res.status(400).json({ ok:false, code:'INVALID_AMOUNT' });
  }
  await payments.ensureOrder(order_id, store_id || null, Number(amount || 0));
  await payments.upsertProviderTxn(order_id, provider_txn_id || null);
  const st = String(status || 'AUTHORIZED').toUpperCase();
  await payments.setStatus(order_id, st, { source:'confirm' });
  return res.json({ ok:true, order_id, status: st });
});

// webhook: raw 먼저(앱 전역 json 파서보다 앞서 mount됨), HMAC + timestamp
router.post('/webhook/pg', express.raw({ type:'application/json' }), async (req, res) => {
  const sig = req.get('X-Webhook-Signature') || req.get('X-Signature') || req.get('Bootpay-Signature');
  const ts  = req.get('X-Webhook-Timestamp') || req.get('X-Timestamp');
  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from('');
  const v = verifySignature(raw, sig, ts);
  if (!v.ok) return res.status(401).json({ ok:false, code:v.code });
  let evt; try { evt = JSON.parse(raw.toString('utf8')); }
  catch { return res.status(400).json({ ok:false, code:'INVALID_JSON' }); }
  const order_id = evt.order_id || evt.orderId || evt.order || null;
  const provider_txn_id = evt.receipt_id || evt.tid || evt.pg_tid || evt.txn_id || evt.transactionId || null;
  const amount = Number(evt.price || evt.amount || 0);
  const label = String(evt.event || evt.status || '').toUpperCase();
  if (!order_id || !label) return res.status(400).json({ ok:false, code:'ORDER_OR_EVENT_REQUIRED' });
  await payments.ensureOrder(order_id, null, amount);
  await payments.upsertProviderTxn(order_id, provider_txn_id);
  let status = 'PENDING';
  if (['AUTHORIZED','APPROVED','AUTH'].includes(label)) status = 'AUTHORIZED';
  else if (['CAPTURED','PAID','DONE','CONFIRMED','SETTLED'].includes(label)) status = 'CAPTURED';
  else if (['CANCEL','CANCELED','REFUNDED'].includes(label)) status = 'CANCELED';
  else if (['FAILED','FAIL','ERROR'].includes(label)) status = 'FAILED';
  await payments.setStatus(order_id, status, { source:'webhook', label, provider_txn_id, ts });
  return res.json({ ok:true });
});

module.exports = router;
JS

# E) app.js 패치: raw 바인딩을 express.json()보다 앞에 강제
if ! grep -q "/billing/webhook/pg" server/app.js; then
  if grep -n "app\.use(.*express\.json" server/app.js >/dev/null; then
    LINE=$(grep -n "app\.use(.*express\.json" server/app.js | head -n1 | cut -d: -f1)
    awk -v ln="$LINE" 'NR==ln{print "app.use(\x27/billing/webhook/pg\x27, require(\x27express\x27).raw({ type: \x27application/json\x27 }));"; print; next}1' server/app.js > server/app.js.r && mv server/app.js.r server/app.js
  else
    echo "app.use('/billing/webhook/pg', require('express').raw({ type: 'application/json' }));" >> server/app.js
  fi
fi
if ! grep -q "routes/payments" server/app.js; then
  if grep -n "app\.use(.*express\.json" server/app.js >/dev/null; then
    LINE=$(grep -n "app\.use(.*express\.json" server/app.js | head -n1 | cut -d: -f1)
    awk -v ln="$LINE" 'NR==ln{print; print "app.use(\x27/billing\x27, require(\x27./routes/payments\x27));"; print "app.get(\x27/openapi_r51.yaml\x27,(req,res)=>res.sendFile(require(\x27path\x27).join(__dirname,\x27openapi\x27,\x27r51.yaml\x27)));"; print "app.get(\x27/docs-payments\x27,(req,res)=>res.sendFile(require(\x27path\x27).join(__dirname,\x27openapi\x27,\x27payments.html\x27)));"; next}1' server/app.js > server/app.js.r && mv server/app.js.r server/app.js
  else
    echo "app.use('/billing', require('./routes/payments'));" >> server/app.js
    echo "app.get('/openapi_r51.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','r51.yaml')));" >> server/app.js
    echo "app.get('/docs-payments',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','payments.html')));" >> server/app.js
  fi
fi

# F) OpenAPI 보강
cat > server/openapi/r51.yaml <<'YAML'
openapi: 3.0.3
info: { title: Petlink Payments API, version: "r5.1" }
servers: [ { url: http://localhost:5902 } ]
components:
  securitySchemes:
    WebhookSignature: { type: apiKey, in: header, name: X-Webhook-Signature }
paths:
  /billing/confirm:
    post:
      summary: Confirm payment after client approval (Idempotent by order_id)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [order_id]
              properties:
                order_id: { type: string }
                provider_txn_id: { type: string, nullable: true }
                amount: { type: integer, minimum: 0 }
                store_id: { type: integer, nullable: true }
                status: { type: string, enum: [AUTHORIZED, CAPTURED, CANCELED], default: AUTHORIZED }
      responses: { '200': { description: OK }, '400': { description: Bad Request } }
  /billing/webhook/pg:
    post:
      summary: Payment gateway webhook (HMAC + Timestamp)
      description: Computes HMAC with: sha256(secret, "ts.body")
      security: [ { WebhookSignature: [] } ]
      parameters:
        - in: header
          name: X-Webhook-Signature
          schema: { type: string }
        - in: header
          name: X-Webhook-Timestamp
          schema: { type: string, example: "1731390000" }
      responses:
        '200': { description: OK }
        '401': { description: Invalid signature or timestamp }
        '400': { description: Invalid payload }
YAML

cat > server/openapi/payments.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Payments API (r5.1)</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css"/>
<div id="swagger"></div>
<script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
<script>window.ui = SwaggerUIBundle({ url: '/openapi_r51.yaml', dom_id: '#swagger' });</script>
HTML

echo "[r5.1v2] apply done"
