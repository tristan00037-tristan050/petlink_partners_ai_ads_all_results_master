const rateLimit = require('express-rate-limit');

const windowSec = parseInt(process.env.RATE_LIMIT_WINDOW_SEC || '60', 10);
const maxReq = parseInt(process.env.RATE_LIMIT_MAX || '120', 10);

module.exports = rateLimit({
  windowMs: windowSec * 1000,
  max: maxReq,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, code: 'RATE_LIMITED', message: '요청이 너무 많습니다.' },
});

