/**
 * P0: Audit Logger 미들웨어
 * 요청 감사 로깅
 */

function auditLogger(req, res, next) {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    const log = {
      timestamp: new Date().toISOString(),
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration,
      req_id: req.req_id,
      ip: req.ip,
      user_id: req.user?.userId || req.user?.id || null,
      admin: req.admin ? true : false
    };
    
    // 성능 로깅 (200ms 이상인 경우)
    if (duration > 200) {
      console.warn('[Audit Slow]', JSON.stringify(log));
    } else {
      console.log('[Audit]', JSON.stringify(log));
    }
  });
  
  next();
}

module.exports = auditLogger;

