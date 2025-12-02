const express = require('express');
const { requireAuth } = require('../mw/authn');
const { pool } = require('../lib/db');
const { markInvoicePaid, autoResumeAfterPayment } = require('../lib/billing');

const router = express.Router();

router.post('/dev/pg/webhook/mock', requireAuth, async (req, res) => {
  if (String(process.env.ENABLE_DEV_MOCK || 'false') !== 'true')
    return res.status(403).json({ ok:false, code:'FORBIDDEN' });

  const { provider='mock', invoice_id, amount_krw=0, type='payment.succeeded' } = req.body || {};

  const eventId = `evt_${Date.now()}`;
  const providerPaymentId = `pay_${Date.now()}`;

  const payload = {
    id: eventId,
    type,
    invoice_id,
    data: {
      object: {
        id: providerPaymentId,
        amount: amount_krw,
        metadata: { invoice_id }
      }
    }
  };

  try {
    // payment_events에 직접 삽입 (멱등)
    await pool.query(
      `INSERT INTO payment_events(provider, event_id, event_type, invoice_id, payload)
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (provider, event_id) DO NOTHING`,
      [provider, eventId, type, invoice_id, payload]
    );

    // payments 레코드 생성/결합 - 기존 payments 테이블 스키마에 맞춤
    let paymentId = null;
    if (providerPaymentId && invoice_id) {
      const upsert = await pool.query(
        `INSERT INTO payments(provider, provider_txn_id, invoice_id, amount, currency, status, metadata)
         VALUES ($1,$2,$3,$4,'KRW','pending',$5::jsonb)
         ON CONFLICT (provider, provider_txn_id) DO UPDATE SET updated_at=now(), invoice_id=EXCLUDED.invoice_id
         RETURNING id`,
        [provider, providerPaymentId, invoice_id, amount_krw, JSON.stringify({ method: 'mock' })]
      );
      paymentId = upsert.rows[0]?.id || null;
    }

    // 결제 성공 처리
    if (invoice_id && (type === 'payment.succeeded' || type === 'paid')) {
      await pool.query('BEGIN');
      try {
        await markInvoicePaid(invoice_id);
        const s = await pool.query(`SELECT store_id FROM invoices WHERE id=$1`, [invoice_id]);
        if (s.rows.length) await autoResumeAfterPayment(s.rows[0].store_id);
        if (paymentId) await pool.query(`UPDATE payments SET status='succeeded', settled_at=now() WHERE id=$1`, [paymentId]);
        await pool.query('COMMIT');
      } catch (e) { await pool.query('ROLLBACK'); throw e; }
    }

    // webhook_logs 기록
    await pool.query(
      `INSERT INTO webhook_logs(provider, event_id, signature_valid, http_status, payload)
       VALUES ($1,$2,$3,$4,$5)`,
      [provider, eventId, true, 200, payload]
    );

    res.json({ ok:true, mock:true, payload });
  } catch (e) {
    console.error('[pg_mock]', e);
    res.status(500).json({ ok:false, error: String(e) });
  }
});

module.exports = router;

