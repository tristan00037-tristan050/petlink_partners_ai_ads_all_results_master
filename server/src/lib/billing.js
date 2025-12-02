const { pool } = require('./db');

async function getActiveSubscription(storeId) {
  const q = `
    SELECT sps.id, sps.plan_code, sps.period_start, sps.period_end
    FROM store_plan_subscriptions sps
    WHERE sps.store_id=$1 AND sps.status='active' AND now() BETWEEN sps.period_start AND sps.period_end
    LIMIT 1`;
  const { rows } = await pool.query(q, [storeId]);
  return rows[0] || null;
}

async function getPlanPriceKRW(plan_code) {
  const { rows } = await pool.query('SELECT price FROM plans WHERE code=$1', [plan_code]);
  return rows.length ? rows[0].price : 0;
}

async function previewInvoice(storeId) {
  const sub = await getActiveSubscription(storeId);
  if (!sub) return { ok:false, code:'NO_ACTIVE_SUBSCRIPTION' };
  const amount = await getPlanPriceKRW(sub.plan_code);
  const due = new Date(sub.period_end);
  return {
    ok: true,
    preview: {
      store_id: storeId,
      subscription_id: sub.id,
      period_start: sub.period_start,
      period_end: sub.period_end,
      due_date: due.toISOString(),
      amount_krw: amount,
      items: [{ description: `Plan ${sub.plan_code}`, amount_krw: amount }]
    }
  };
}

async function createInvoiceFromPreview(prev) {
  const { store_id, subscription_id, period_start, period_end, due_date, amount_krw, items } = prev;
  const ins = await pool.query(
    `INSERT INTO invoices (store_id, subscription_id, period_start, period_end, due_date, amount_krw, status)
     VALUES ($1,$2,$3,$4,$5,$6,'pending')
     RETURNING id, status`, [store_id, subscription_id, period_start, period_end, due_date, amount_krw]
  );
  const invId = ins.rows[0].id;
  for (const it of (items || [])) {
    await pool.query(
      `INSERT INTO invoice_items (invoice_id, description, amount_krw) VALUES ($1,$2,$3)`,
      [invId, it.description, it.amount_krw]
    );
  }
  return invId;
}

async function markPaid(invoiceId) {
  await pool.query(`UPDATE invoices SET status='paid', paid_at=now() WHERE id=$1`, [invoiceId]);
}

async function hasOverdueInvoices(storeId) {
  const { rows } = await pool.query(
    `SELECT 1 FROM invoices WHERE store_id=$1 AND status='overdue' LIMIT 1`, [storeId]
  );
  return rows.length > 0;
}

async function markInvoicePaid(invoiceId) {
  await pool.query(`UPDATE invoices SET status='paid', paid_at=now() WHERE id=$1`, [invoiceId]);
}

/**
 * 결제 완료 후 자동 재개:
 * - 최신 상태 이력(reason_code)이 'blocked_by_billing'인 캠페인만 재개
 * - 미해결 정책 위반(pv.resolved_at IS NULL) 있는 캠페인은 제외
 */
async function autoResumeAfterPayment(storeId) {
  if (String(process.env.BILLING_AUTO_RESUME || process.env.AUTO_RESUME_ON_PAYMENT || 'false') !== 'true') {
    return 0;
  }
  const q = `
    WITH latest AS (
      SELECT h.campaign_id, h.reason_code, h.created_at,
             ROW_NUMBER() OVER (PARTITION BY h.campaign_id ORDER BY h.created_at DESC) AS rn
      FROM campaign_status_history h
      JOIN campaigns c ON c.id=h.campaign_id
      WHERE c.store_id=$1
    ),
    target AS (
      SELECT l.campaign_id
      FROM latest l
      JOIN campaigns c ON c.id=l.campaign_id
      WHERE l.rn=1
        AND c.status='paused'
        AND l.reason_code='blocked_by_billing'
        AND NOT EXISTS (
          SELECT 1 FROM policy_violations pv
          WHERE pv.entity_type='campaign' AND pv.entity_id=c.id AND pv.resolved_at IS NULL
        )
    )
    UPDATE campaigns c
       SET status='active'
      FROM target t
     WHERE c.id=t.campaign_id
  RETURNING c.id`;
  const { rows } = await pool.query(q, [storeId]);

  for (const r of rows) {
    await pool.query(
      `INSERT INTO campaign_status_history (campaign_id, from_status, to_status, reason_code, note)
       VALUES ($1,'paused','active','resume_after_payment','auto')`,
      [r.id]
    );
  }
  return rows.length;
}

module.exports = { previewInvoice, createInvoiceFromPreview, markPaid, hasOverdueInvoices, markInvoicePaid, autoResumeAfterPayment };

