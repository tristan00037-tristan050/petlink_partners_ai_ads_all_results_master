/**
 * P0: CORS Split 미들웨어
 * App과 Admin의 CORS 분리
 */

const APP_ORIGIN = process.env.APP_ORIGIN || 'http://localhost:5902';
const ADMIN_ORIGIN = process.env.ADMIN_ORIGIN || 'http://localhost:8000';

/**
 * App CORS 미들웨어
 */
function appCORS(req, res, next) {
  const origin = req.headers.origin;
  
  if (origin === APP_ORIGIN) {
    res.setHeader('Access-Control-Allow-Origin', APP_ORIGIN);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  
  next();
}

/**
 * Admin CORS 미들웨어
 */
function adminCORS(req, res, next) {
  const origin = req.headers.origin;
  
  if (origin === ADMIN_ORIGIN) {
    res.setHeader('Access-Control-Allow-Origin', ADMIN_ORIGIN);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Admin-Key');
  }
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  
  next();
}

module.exports = {
  appCORS,
  adminCORS
};

