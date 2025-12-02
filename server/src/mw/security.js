const helmet = require('helmet');
const cors = require('cors');

module.exports = function security(app) {
  // Helmet 설정에서 CORS 관련 헤더는 제외 (CORS 미들웨어가 처리)
  // contentSecurityPolicy를 false로 설정하여 CORS 헤더가 덮어씌워지지 않도록 함
  app.use(helmet({
    contentSecurityPolicy: false, // CSP가 CORS 헤더를 방해할 수 있음
    crossOriginResourcePolicy: false, // CORS 미들웨어가 처리
    crossOriginOpenerPolicy: false,   // CORS 미들웨어가 처리
    // CORS 헤더를 덮어쓰지 않도록 추가 설정
    hsts: false, // HSTS가 CORS 헤더를 방해할 수 있음
  }));
  // CORS는 index.js에서 이미 설정되므로 여기서는 제거
  // app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
};

