const express = require('express');
const { pool } = require('../lib/db');
const router = express.Router();

router.get('/health', (req, res) => {
  res.json({ ok: true, service: 'P0 API', version: '1.0.0', timestamp: new Date().toISOString() });
});

router.get('/healthz/deep', async (_req, res, next) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true, deps: { db: 'up' }, ts: new Date().toISOString() });
  } catch (err) { next(err); }
});

module.exports = router;

