const express = require('express');
const { verifyHmac } = require('../lib/pg_sign');
const { pool } = require('../lib/db');
const { markInvoicePaid, autoResumeAfterPayment } = require('../lib/billing');
const raw = require('body-parser').raw({ type: '*/*' }); // 원문 필요

const router = express.Router();

function secretFor(provider) {
  const p = provider.toUpperCase();
  return process.env[`PG_${p}_WEBHOOK_SECRET`] || '';
}

async function upsertEvent(provider, eventId, eventType, paymentId, invoiceId, payload) {
  // 멱등: (provider,event_id) UNIQUE
  await pool.query(
    `INSERT INTO payment_events(provider, event_id, event_type, payment_id, invoice_id, payload)
     VALUES ($1,$2,$3,$4,$5,$6)
     ON CONFLICT (provider, event_id) DO NOTHING`,
    [provider, eventId, eventType, paymentId, invoiceId, payload]
  );
}

router.post('/pg/webhook/:provider', raw, async (req, res) => {
  const provider = String(req.params.provider || '').toLowerCase();
  const sig = req.header('X-PG-Signature') || req.header('Stripe-Signature') || '';
  const secret = secretFor(provider);
  const bodyRaw = req.body;
  let code = 200, valid = false, payload = {};

  try {
    // Mock provider는 서명 검증 스킵
    if (provider === 'mock' || !secret) {
      valid = true;
    } else {
      valid = verifyHmac(bodyRaw, sig, secret);
    }

    payload = JSON.parse(bodyRaw.toString('utf8'));
    const eventId = payload.id || payload.event_id || payload.requestId || '';
    const type = payload.type || payload.event || payload.status || 'unknown';

    // 표준화: invoice_id는 metadata에 실려온다고 가정 (PG 설정에서 전송)
    const invoiceId = Number(
      payload?.data?.object?.metadata?.invoice_id
      ?? payload?.metadata?.invoice_id
      ?? payload?.invoice_id
      ?? 0
    ) || null;

    let paymentId = null;
    const providerPaymentId =
      payload?.data?.object?.id || payload?.paymentId || payload?.data?.paymentId || null;

    // 결제 레코드 생성/결합(멱등) - 기존 payments 테이블 스키마에 맞춤
    if (providerPaymentId && invoiceId) {
      const amount = payload?.data?.object?.amount || payload?.amount || 0;
      const upsert = await pool.query(
        `INSERT INTO payments(provider, provider_txn_id, invoice_id, amount, currency, status, metadata)
         VALUES ($1,$2,$3,COALESCE($4,0),'KRW','pending',$5::jsonb)
         ON CONFLICT (provider, provider_txn_id) DO UPDATE SET updated_at=now(), invoice_id=EXCLUDED.invoice_id
         RETURNING id`,
        [
          provider,
          providerPaymentId,
          invoiceId,
          amount,
          JSON.stringify({ method: payload?.data?.object?.method || payload?.method || null })
        ]
      );
      paymentId = upsert.rows[0]?.id || null;
    }

    await upsertEvent(provider, eventId, type, paymentId, invoiceId, payload);

    // 이벤트 매핑 (예: 'payment.succeeded' / 'PAYMENT_SUCCEEDED' 등)
    const t = String(type).toLowerCase();
    if (invoiceId && (t.includes('succeeded') || t === 'paid')) {
      // 인보이스 결제 처리
      await pool.query('BEGIN');
      try {
        await markInvoicePaid(invoiceId);
        const s = await pool.query(`SELECT store_id FROM invoices WHERE id=$1`, [invoiceId]);
        if (s.rows.length) await autoResumeAfterPayment(s.rows[0].store_id);
        if (paymentId) await pool.query(`UPDATE payments SET status='succeeded', settled_at=now() WHERE id=$1`, [paymentId]);
        await pool.query('COMMIT');
      } catch (e) { await pool.query('ROLLBACK'); throw e; }
    } else if (invoiceId && (t.includes('failed') || t === 'failed')) {
      if (paymentId) await pool.query(`UPDATE payments SET status='failed' WHERE id=$1`, [paymentId]);
    }

    code = 200;
    res.status(200).json({ ok: true });
  } catch (e) {
    code = 400;
    console.error('[pg_webhook]', e);
    res.status(200).json({ ok: true }); // 대부분 PG는 200을 기대(재시도 방지). 실패는 로그로 남김.
  } finally {
    // 원본 웹훅 로그
    try {
      await pool.query(
        `INSERT INTO webhook_logs(provider, event_id, signature_valid, http_status, payload)
         VALUES ($1,$2,$3,$4,$5)`,
        [provider, payload?.id || payload?.event_id || null, valid, code, payload]
      );
    } catch { /* no-op */ }
  }
});

module.exports = router;

