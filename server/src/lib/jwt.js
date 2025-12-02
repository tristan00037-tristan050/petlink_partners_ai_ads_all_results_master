const jwt = require('jsonwebtoken');
const secret = process.env.JWT_SECRET;
const ttl = parseInt(process.env.JWT_TTL_SEC || '3600', 10);

if (!secret) throw new Error('JWT_SECRET 미설정');

module.exports = {
  sign(payload, opt = {}) {
    return jwt.sign(payload, secret, { expiresIn: ttl, ...opt });
  },
  verify(token) {
    return jwt.verify(token, secret);
  },
};

