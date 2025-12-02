/**
 * P0: Admin Gate 미들웨어
 * X-Admin-Key 헤더 검증
 */

const ADMIN_KEY = process.env.ADMIN_KEY || 'admin-dev-key-123';

/**
 * Admin 인증 미들웨어
 */
function requireAdmin(req, res, next) {
  const adminKey = req.headers['x-admin-key'];

  if (!adminKey || adminKey !== ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  // Admin 정보 설정 (옵션)
  req.admin = {
    sub: 'admin',
    role: 'admin'
  };

  next();
}

module.exports = {
  requireAdmin
};

