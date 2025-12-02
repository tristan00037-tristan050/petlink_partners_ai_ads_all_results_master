const express = require('express');
const { request } = require('undici');

const router = express.Router();
const BASE = process.env.INTERNAL_BASE_URL || 'http://localhost:5903';

function setAuthCookie(res, token) {
  const name = process.env.COOKIE_NAME || 'access_token';
  const domain = process.env.COOKIE_DOMAIN || undefined;
  const secure = String(process.env.COOKIE_SECURE || 'false') === 'true';
  const sameSite = process.env.COOKIE_SAMESITE || 'Lax';
  res.cookie(name, token, {
    httpOnly: true,
    secure,
    sameSite,          // 'Lax' or 'Strict'
    domain,
    path: '/',
    maxAge: 1000 * 60 * 60 * 24 * 7 // 7d
  });
}

function clearAuthCookie(res) {
  const name = process.env.COOKIE_NAME || 'access_token';
  const domain = process.env.COOKIE_DOMAIN || undefined;
  res.clearCookie(name, { httpOnly: true, domain, path: '/' });
}

/** 로그인 -> JWT 발급 -> HttpOnly 쿠키 설정 */
router.post('/login', express.json(), async (req, res) => {
  try {
    const r = await request(`${BASE}/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: req.body.email, password: req.body.password })
    });
    const data = await r.body.json();
    if (!data || !data.token) return res.status(401).json({ ok:false, code:'AUTH_FAIL' });
    setAuthCookie(res, data.token);
    res.json({ ok:true });
  } catch (e) {
    res.status(500).json({ ok:false, code:'BFF_LOGIN_ERR' });
  }
});

/** 세션 사용자 */
router.get('/me', async (req, res) => {
  try {
    // authnCookieBridge가 Authorization 헤더를 셋업함
    const r = await request(`${BASE}/auth/me`, { method:'GET', headers: { authorization: req.headers.authorization || '' }});
    const data = await r.body.json();
    res.status(r.statusCode).json(data);
  } catch {
    res.status(401).json({ ok:false, code:'UNAUTHENTICATED' });
  }
});

/** 로그아웃 */
router.post('/logout', (_req, res) => {
  clearAuthCookie(res);
  res.json({ ok:true });
});

module.exports = router;

