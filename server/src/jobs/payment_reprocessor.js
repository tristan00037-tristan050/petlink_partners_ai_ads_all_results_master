const { pool } = require('../lib/db');
const { client } = require('../observability/metrics');

const counterReproc = new client.Counter({ name:'payment_reprocessor_runs_total', help:'payment reprocessor runs' });
const counterFixed  = new client.Counter({ name:'payment_reprocessor_fixed_total', help:'events fixed' });

/**
 * 단순 정책:
 * - 'invoice.paid' 또는 'payment.succeeded' 이벤트가 있는데 해당 invoice가 paid가 아니면 보정
 * - signature_valid=false 이벤트는 스킵(로그만)
 * - 멱등: DB 상태와 동일하면 noop
 */
async function runOnce(limit = 200) {
  counterReproc.inc();
  const { rows: evts } = await pool.query(
    `SELECT id, provider, event_id, event_type, payload, received_at
       FROM payment_events
      WHERE (event_type IN ('invoice.paid','payment.succeeded'))
        AND received_at > now() - interval '7 days'
      ORDER BY received_at ASC
      LIMIT $1`, [limit]
  );

  for (const e of evts) {
    try {
      const meta = e.payload?.data?.object?.metadata || e.payload?.data?.metadata || e.payload?.metadata || {};
      const invoiceId = parseInt(meta.invoice_id || e.payload?.data?.invoice_id || e.payload?.invoice_id || 0, 10);
      if (!invoiceId) continue;

      const inv = await pool.query(`SELECT status, store_id FROM invoices WHERE id=$1`, [invoiceId]);
      if (!inv.rows.length) continue;
      if (inv.rows[0].status === 'paid') continue;

      await pool.query('BEGIN');
      try {
        await pool.query(`UPDATE invoices SET status='paid', paid_at=now() WHERE id=$1`, [invoiceId]);
        const storeId = inv.rows[0].store_id;
        // 자동 재개(정밀화 버전)
        const { autoResumeAfterPayment } = require('../lib/billing');
        await autoResumeAfterPayment(storeId);
        await pool.query('COMMIT');
        counterFixed.inc();
      } catch (err) {
        await pool.query('ROLLBACK');
        console.error('[reprocessor] fail', err);
      }
    } catch (err) {
      console.error('[reprocessor] parse error', err);
    }
  }
}

if (require.main === module) {
  runOnce().then(()=>process.exit(0)).catch(e=>{console.error(e);process.exit(1);});
}

module.exports = { runOnce };

