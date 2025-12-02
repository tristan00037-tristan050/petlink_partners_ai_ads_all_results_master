const express = require('express');
const { pool } = require('../lib/db');
const { hash, compare } = require('../lib/hash');
const { assertSignup } = require('../schema/auth');
const { sign } = require('../lib/jwt');
const { requireAuth } = require('../mw/authn');
const router = express.Router();

router.post('/signup', async (req, res, next) => {
  try {
    const { email, password, tenant } = assertSignup(req.body);
    const pw = await hash(password);
    const q = `
      INSERT INTO users (email, password_hash, tenant, role)
      VALUES ($1, $2, $3, 'user')
      ON CONFLICT (email) DO NOTHING
      RETURNING id, email, tenant, role, created_at
    `;
    const { rows } = await pool.query(q, [email, pw, tenant]);
    if (rows.length === 0) return res.json({ ok: true, created: false, reason: 'exists' });
    res.json({ ok: true, created: true, user: rows[0] });
  } catch (err) { next(err); }
});

router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ ok: false, code: 'BAD_REQUEST', message: 'email/password 필수' });
    }
    const { rows } = await pool.query('SELECT id, email, password_hash, tenant, role FROM users WHERE email=$1', [String(email)]);
    if (rows.length === 0) return res.status(401).json({ ok: false, code: 'UNAUTHORIZED', message: '인증 실패' });
    const u = rows[0];
    const ok = await compare(String(password), u.password_hash);
    if (!ok) return res.status(401).json({ ok: false, code: 'UNAUTHORIZED', message: '인증 실패' });

    const token = sign({ sub: u.id, email: u.email, tenant: u.tenant, role: u.role });
    res.json({ ok: true, token, user: { id: u.id, email: u.email, tenant: u.tenant, role: u.role } });
  } catch (err) { next(err); }
});

router.get('/me', requireAuth, async (req, res, next) => {
  try {
    // 토큰 클레임을 신뢰하되, 계정 존재/상태 확인용 최소 조회(선택)
    const { rows } = await pool.query('SELECT id, email, tenant, role, created_at FROM users WHERE id=$1', [req.user.sub]);
    if (rows.length === 0) return res.status(404).json({ ok: false, code: 'NOT_FOUND', message: '사용자 없음' });
    res.json({ ok: true, user: rows[0] });
  } catch (err) { next(err); }
});

module.exports = router;

