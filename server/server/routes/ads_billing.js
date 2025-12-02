const express=require('express');
const ads=require('../lib/ads_billing');
const db=require('../lib/db');
const adapter = require('../lib/billing/factory')();
const router=express.Router();

// webhook signature verification을 위한 별도 어댑터 (기존 호환성)
const webhookAdapter = require('../adapters/billing');

function verifySignature(rawBuf, req){
  const secret = process.env.PAYMENT_WEBHOOK_SECRET || '';
  const ts = req.get('X-Webhook-Timestamp');
  const sig = req.get('X-Webhook-Signature');
  return webhookAdapter.webhookVerify({raw: rawBuf, ts, sig, secret});
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

module.exports = router;
