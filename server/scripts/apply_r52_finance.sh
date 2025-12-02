#!/usr/bin/env bash
set -euo pipefail
mkdir -p scripts/migrations server/routes server/openapi

# 1) 마이그레이션
cat > scripts/migrations/20251112_r52.sql <<'SQL'
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refunded_total INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS settled_at timestamptz;

CREATE TABLE IF NOT EXISTS refunds (
  id BIGSERIAL PRIMARY KEY,
  refund_id TEXT UNIQUE,
  order_id TEXT NOT NULL REFERENCES payments(order_id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  reason TEXT,
  status TEXT NOT NULL CHECK (status IN ('REQUESTED','SUCCEEDED','FAILED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refunds_order_id ON refunds(order_id);

CREATE TABLE IF NOT EXISTS settlements (
  id BIGSERIAL PRIMARY KEY,
  payment_id BIGINT REFERENCES payments(id) ON DELETE CASCADE,
  order_id TEXT NOT NULL,
  gross INTEGER NOT NULL,
  fee INTEGER NOT NULL,
  net INTEGER NOT NULL,
  settled_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_settlements_order_id ON settlements(order_id);
SQL

# 2) 환불 라우트
cat > server/routes/payments_refund.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const outbox=require('../lib/outbox');
const router=express.Router();

router.post('/refund', express.json(), async (req,res)=>{
  const {order_id, amount, reason, refund_id} = req.body||{};
  const amt = Number(amount);
  if(!order_id || !Number.isFinite(amt) || amt<=0) return res.status(400).json({ok:false, code:'INVALID_INPUT'});
  try{
    await db.transaction(async (c)=>{
      const p = await c.query(`SELECT id, amount, status, refunded_total FROM payments WHERE order_id=$1 FOR UPDATE`, [order_id]);
      if(!p.rows.length) throw Object.assign(new Error('PAYMENT_NOT_FOUND'), {status:404, code:'PAYMENT_NOT_FOUND'});
      const row = p.rows[0];
      if(row.status!=='CAPTURED') throw Object.assign(new Error('INVALID_STATE'), {status:409, code:'REFUND_NOT_ALLOWED_IN_STATE'});
      if(refund_id){
        const ex = await c.query(`SELECT amount,status FROM refunds WHERE refund_id=$1`, [refund_id]);
        if(ex.rows.length){
          if(ex.rows[0].amount===amt && ex.rows[0].status==='SUCCEEDED'){ return res.json({ok:true, order_id, refunded: amt}); }
          throw Object.assign(new Error('REPLAY_MISMATCH'), {status:409, code:'REFUND_REPLAY_MISMATCH'});
        }
      }
      const remaining = row.amount - row.refunded_total;
      if(amt > remaining) throw Object.assign(new Error('AMOUNT_EXCEEDS'), {status:409, code:'REFUND_EXCEEDS_REMAINING'});
      await c.query(`INSERT INTO refunds(refund_id,order_id,amount,reason,status) VALUES($1,$2,$3,$4,'SUCCEEDED')`,
                    [refund_id||null, order_id, amt, reason||null]);
      await c.query(`UPDATE payments SET refunded_total=refunded_total+$2,
                      status=CASE WHEN refunded_total+$2 >= amount THEN 'CANCELED' ELSE status END,
                      updated_at=now() WHERE order_id=$1`, [order_id, amt]);
      const pay = await c.query(`SELECT id,status,refunded_total FROM payments WHERE order_id=$1`,[order_id]);
      await outbox.addEventTx(c,'PAYMENT_REFUND_SUCCEEDED','payment', pay.rows[0].id, {order_id, amount:amt, reason});
      if(pay.rows[0].status==='CANCELED'){
        await outbox.addEventTx(c,'PAYMENT_CANCELED','payment', pay.rows[0].id, {order_id});
      }
    });
    return res.json({ok:true, order_id, refunded: amt});
  }catch(e){
    const sc = e.status || 500, code = e.code || 'REFUND_ERROR';
    return res.status(sc).json({ok:false, code});
  }
});

module.exports=router;
JS

# 3) 정산/컴플라이언스 Admin 라우트
cat > server/routes/admin_settlements.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const router=express.Router();

router.post('/snapshot', async (req,res)=>{
  const bps = parseInt(process.env.SETTLEMENT_FEE_BPS || '300', 10); // 3%
  let cnt=0;
  await db.transaction(async(c)=>{
    const q = await c.query(`SELECT id, order_id, amount, refunded_total FROM payments WHERE status='CAPTURED' AND settled_at IS NULL`);
    for(const row of q.rows){
      const gross = row.amount - row.refunded_total;
      const fee = Math.floor(gross * bps / 10000);
      const net = gross - fee;
      await c.query(`INSERT INTO settlements(payment_id,order_id,gross,fee,net,settled_at) VALUES($1,$2,$3,$4,$5, now())`,
                    [row.id,row.order_id,gross,fee,net]);
      await c.query(`UPDATE payments SET settled_at=now() WHERE id=$1`, [row.id]);
      cnt++;
    }
  });
  res.json({ok:true, settled: cnt});
});

module.exports=router;
JS

cat > server/routes/admin_compliance.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const router=express.Router();

router.post('/sanitize', async (req,res)=>{
  const {rows} = await db.q(`UPDATE payments
    SET metadata = COALESCE(metadata,'{}')::jsonb - 'card_number' - 'card' - 'customer' - 'email'
    WHERE metadata ?| array['card_number','card','customer','email']
    RETURNING order_id`);
  res.json({ok:true, redacted: rows.length});
});

module.exports=router;
JS

# 4) app.js 장착
if ! grep -q "routes/payments_refund" server/app.js; then
  if grep -n "app\.use(.*express\.json" server/app.js >/dev/null; then
    L=$(grep -n "app\.use(.*express\.json" server/app.js | head -n1 | cut -d: -f1)
    awk -v ln="$L" 'NR==ln{print; print "app.use(\x27/billing\x27, require(\x27./routes/payments_refund\x27));"; next}1' server/app.js > server/app.js.r && mv server/app.js.r server/app.js
  else
    echo "app.use('/billing', require('./routes/payments_refund'));" >> server/app.js
  fi
fi

if ! grep -q "admin/settlements" server/app.js; then
  if grep -n "require('./mw/admin')" server/app.js >/dev/null; then
    L=$(grep -n "require('./mw/admin')" server/app.js | head -n1 | cut -d: -f1)
    awk -v ln="$L" 'NR==ln{print; print "app.use(\x27/admin/settlements\x27, require(\x27./mw/admin\x27).requireAdmin, require(\x27./routes/admin_settlements\x27));"; print "app.use(\x27/admin/ops/compliance\x27, require(\x27./mw/admin\x27).requireAdmin, require(\x27./routes/admin_compliance\x27));"; next}1' server/app.js > server/app.js.r && mv server/app.js.r server/app.js
  else
    echo "app.use('/admin/settlements', require('./mw/admin').requireAdmin, require('./routes/admin_settlements'));" >> server/app.js
    echo "app.use('/admin/ops/compliance', require('./mw/admin').requireAdmin, require('./routes/admin_compliance'));" >> server/app.js
  fi
fi

# 5) OpenAPI(r52)
cat > server/openapi/r52.yaml <<'YAML'
openapi: 3.0.3
info: { title: Petlink Finance API, version: "r5.2" }
servers: [ { url: http://localhost:5902 } ]
paths:
  /billing/refund:
    post:
      summary: Create refund (full or partial)
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [order_id, amount]
              properties:
                order_id: { type: string }
                amount: { type: integer, minimum: 1 }
                reason: { type: string }
                refund_id: { type: string, description: "idempotent client-supplied id" }
      responses:
        '200': { description: OK }
        '409': { description: Exceeds remaining / replay mismatch }
  /admin/settlements/snapshot:
    post:
      summary: Materialize settlements for captured payments
      responses: { '200': { description: OK } }
  /admin/ops/compliance/sanitize:
    post:
      summary: Remove PII-like keys from payments.metadata
      responses: { '200': { description: OK } }
YAML


