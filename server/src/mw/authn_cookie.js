const cookie = require('cookie');

function authnCookieBridge(req, _res, next) {
  if (req.headers.authorization) return next();
  const raw = req.headers.cookie || '';
  const parsed = cookie.parse(raw || '');
  const token = parsed[process.env.COOKIE_NAME || 'access_token'];
  if (token) req.headers.authorization = `Bearer ${token}`;
  next();
}

module.exports = { authnCookieBridge };

