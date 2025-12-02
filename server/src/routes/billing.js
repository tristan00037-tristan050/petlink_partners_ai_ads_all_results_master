const express = require('express');
const { requireAuth } = require('../mw/authn');
const { pool } = require('../lib/db');
const { previewInvoice, createInvoiceFromPreview, markPaid } = require('../lib/billing');

const router = express.Router();

async function ensureMember(storeId, user) {
  const q = `
    SELECT 1 FROM stores s
    LEFT JOIN store_members m ON m.store_id=s.id AND m.user_id=$2 AND m.role IN ('owner','manager')
    WHERE s.id=$1 AND s.tenant=$3 AND (s.owner_user_id=$2 OR m.user_id=$2)
    LIMIT 1`;
  const { rows } = await pool.query(q, [storeId, user.sub, user.tenant]);
  return rows.length > 0;
}

/** 청구 미리보기 */
router.get('/stores/:id/billing/preview', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const out = await previewInvoice(storeId);
    if (!out.ok) return res.status(400).json(out);
    res.json(out);
  } catch (e) { next(e); }
});

/** 미리보기로 인보이스 발행 */
router.post('/stores/:id/billing/invoices', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const out = await previewInvoice(storeId);
    if (!out.ok) return res.status(400).json(out);
    const id = await createInvoiceFromPreview(out.preview);
    res.json({ ok:true, invoice_id:id });
  } catch (e) { next(e); }
});

/** (DEV) 모의 결제 & 모의 연체 생성 */
router.post('/dev/stores/:id/billing/mock', requireAuth, async (req, res, next) => {
  try {
    if (String(process.env.ENABLE_DEV_MOCK || 'false') !== 'true') {
      return res.status(403).json({ ok:false, code:'FORBIDDEN' });
    }
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const { action, invoice_id } = req.body || {};
    if (action === 'pay' && invoice_id) {
      await markPaid(parseInt(invoice_id, 10));
      return res.json({ ok:true, action:'paid', invoice_id });
    }
    if (action === 'make_overdue') {
      await pool.query(`UPDATE invoices SET status='overdue', due_date=now() - interval '1 day' WHERE store_id=$1 AND status='pending'`, [storeId]);
      return res.json({ ok:true, action:'overdue_marked' });
    }
    return res.status(400).json({ ok:false, code:'BAD_REQUEST' });
  } catch (e) { next(e); }
});

/** 인보이스 목록 */
router.get('/stores/:id/billing/invoices', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const { rows } = await pool.query(
      `SELECT id, status, amount_krw, period_start, period_end, due_date, paid_at, created_at
       FROM invoices WHERE store_id=$1 ORDER BY id DESC`, [storeId]
    );
    res.json({ ok:true, items: rows });
  } catch (e) { next(e); }
});

module.exports = router;

