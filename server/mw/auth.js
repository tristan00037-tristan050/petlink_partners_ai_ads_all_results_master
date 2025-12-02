/**
 * P0: Auth 미들웨어
 * JWT 토큰 발급 및 검증
 */

const crypto = require('crypto');

const JWT_SECRET = process.env.JWT_SECRET || 'p0-jwt-secret-key-change-in-production';
const JWT_EXPIRY = 15 * 60 * 1000; // 15분

/**
 * JWT 토큰 발급
 */
function issue(payload) {
  const header = {
    alg: 'HS256',
    typ: 'JWT'
  };

  const now = Date.now();
  const tokenPayload = {
    ...payload,
    iat: now,
    exp: now + JWT_EXPIRY
  };

  const headerB64 = Buffer.from(JSON.stringify(header)).toString('base64url');
  const payloadB64 = Buffer.from(JSON.stringify(tokenPayload)).toString('base64url');
  const signature = crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`${headerB64}.${payloadB64}`)
    .digest('base64url');

  return `${headerB64}.${payloadB64}.${signature}`;
}

/**
 * JWT 토큰 검증
 */
function verify(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) {
      return null;
    }

    const [headerB64, payloadB64, signature] = parts;
    const expectedSignature = crypto
      .createHmac('sha256', JWT_SECRET)
      .update(`${headerB64}.${payloadB64}`)
      .digest('base64url');

    if (signature !== expectedSignature) {
      return null;
    }

    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString());
    
    // 만료 확인
    if (payload.exp && payload.exp < Date.now()) {
      return null;
    }

    return payload;
  } catch (error) {
    return null;
  }
}

/**
 * 인증 미들웨어
 */
function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  const token = authHeader.substring(7);
  const payload = verify(token);

  if (!payload) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '유효하지 않은 토큰입니다.'
    });
  }

  req.user = payload;
  next();
}

module.exports = {
  issue,
  verify,
  requireAuth
};

