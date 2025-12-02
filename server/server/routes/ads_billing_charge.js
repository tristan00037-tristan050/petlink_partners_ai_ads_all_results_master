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
