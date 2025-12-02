const express = require('express');
const crypto = require('crypto');
const payments = require('../lib/payments');

const router = express.Router();

function verifySignature(rawBuf, req) {
  const secret = process.env.PAYMENT_WEBHOOK_SECRET || '';
  if (!secret) return { ok:false, code:'SECRET_EMPTY' };
  const ts = req.get('X-Webhook-Timestamp');
  const sig = req.get('X-Webhook-Signature');
  const now = Math.floor(Date.now()/1000);
  const t = parseInt(ts || '0', 10);
  if (!t || Math.abs(now - t) > 300) return { ok:false, code:'TS_WINDOW_EXCEEDED' };
  const mac = crypto.createHmac('sha256', secret)
                    .update(String(t)).update('.').update(rawBuf)
                    .digest('hex');
  try {
    // hex 문자열을 직접 비교 (timingSafeEqual은 Buffer 비교용)
    // sig가 hex 문자열이므로 mac과 직접 비교
    if (!sig || sig.length !== mac.length) return { ok:false, code:'SIG_MISMATCH' };
    // timingSafeEqual을 사용하려면 Buffer로 변환
    const macBuf = Buffer.from(mac, 'hex');
    const sigBuf = Buffer.from(sig, 'hex');
    if (macBuf.length !== sigBuf.length) return { ok:false, code:'SIG_MISMATCH' };
    const ok = crypto.timingSafeEqual(macBuf, sigBuf);
    return ok ? { ok:true } : { ok:false, code:'SIG_MISMATCH' };
  } catch (e) { 
    // 오류 발생 시 상세 정보 로깅 (개발용)
    if (process.env.NODE_ENV === 'development') {
      console.error('[verifySignature]', e.message, { macLength: mac.length, sigLength: (sig || '').length });
    }
    return { ok:false, code:'SIG_VERIFY_ERROR' }; 
  }
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
  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from('');
  const v = verifySignature(raw, req);
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
  
  // 현재 상태 확인
  const current = await payments.getStatus(order_id);
  const currentStatus = current ? current.status : 'PENDING';
  
  let status = 'PENDING';
  if (['AUTHORIZED','APPROVED','AUTH'].includes(label)) status = 'AUTHORIZED';
  else if (['CAPTURED','PAID','DONE','CONFIRMED','SETTLED'].includes(label)) status = 'CAPTURED';
  else if (['CANCEL','CANCELED','REFUNDED'].includes(label)) status = 'CANCELED';
  else if (['FAILED','FAIL','ERROR'].includes(label)) status = 'FAILED';
  
  // CAPTURED로 전이하려면 먼저 AUTHORIZED 상태여야 함
  if (status === 'CAPTURED' && currentStatus === 'PENDING') {
    await payments.setStatus(order_id, 'AUTHORIZED', { source:'webhook', label, provider_txn_id, timestamp: req.get('X-Webhook-Timestamp') || String(Math.floor(Date.now()/1000)) });
  }
  
  const ts = req.get('X-Webhook-Timestamp') || String(Math.floor(Date.now()/1000));
  await payments.setStatus(order_id, status, { source:'webhook', label, provider_txn_id, timestamp: ts });
  return res.json({ ok:true });
});

module.exports = router;
