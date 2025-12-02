const { verify } = require('../lib/jwt');

function parseAuth(req, _res, next) {
  try {
    const h = req.headers['authorization'] || '';
    const [type, token] = h.split(' ');
    if (type === 'Bearer' && token) {
      req.user = verify(token); // { sub, email, tenant, role, iat, exp }
    }
  } catch (e) {
    // 무음 통과(보호 라우트는 requireAuth가 차단)
  } finally {
    next();
  }
}

function requireAuth(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ ok: false, code: 'UNAUTHORIZED', message: '인증이 필요합니다.' });
  }
  next();
}

module.exports = { parseAuth, requireAuth };

