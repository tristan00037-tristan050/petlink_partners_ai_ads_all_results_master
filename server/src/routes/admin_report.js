const express = require('express');
const { pool } = require('../lib/db');
const { requireAdmin } = require('../mw/admin');

const router = express.Router();

router.get('/admin/reports/summary', requireAdmin, async (_req, res, next) => {
  try {
    const [{ rows: a }, { rows: b }, { rows: c }] = await Promise.all([
      pool.query(`SELECT COUNT(*)::int AS users FROM users`),
      pool.query(`SELECT COUNT(*)::int AS stores FROM stores`),
      pool.query(`SELECT COUNT(*) FILTER (WHERE status='active')::int AS active,
                         COUNT(*) FILTER (WHERE status='paused')::int AS paused,
                         COUNT(*)::int AS total
                    FROM campaigns`)
    ]);
    res.json({ ok:true, users:a[0].users, stores:b[0].stores, campaigns:c[0] });
  } catch (e) { next(e); }
});

router.get('/admin/reports/billing', requireAdmin, async (_req, res, next) => {
  try {
    const { rows } = await pool.query(
      `SELECT status, COUNT(*)::int AS cnt, COALESCE(SUM(amount_krw),0)::int AS amount
         FROM invoices GROUP BY status ORDER BY status`
    );
    res.json({ ok:true, invoices: rows });
  } catch (e) { next(e); }
});

module.exports = router;

