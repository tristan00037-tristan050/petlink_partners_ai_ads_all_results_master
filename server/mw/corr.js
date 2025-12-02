/**
 * P0: Correlation ID 미들웨어
 * 요청 추적을 위한 ID 생성
 */

const { randomUUID } = require('crypto');

function correlationId(req, res, next) {
  req.req_id = req.headers['x-request-id'] || randomUUID();
  res.setHeader('X-Request-ID', req.req_id);
  next();
}

module.exports = correlationId;

