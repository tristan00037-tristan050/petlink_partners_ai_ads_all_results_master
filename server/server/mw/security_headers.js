module.exports = function securityHeaders(req, res, next){
  try{
    const APP_ORIGIN   = process.env.APP_ORIGIN   || 'http://localhost:3000';
    const ADMIN_ORIGIN = process.env.ADMIN_ORIGIN || 'http://localhost:8000';
    const csp = [
      "default-src 'self'",
      "base-uri 'none'",
      "frame-ancestors 'none'",
      "object-src 'none'",
      "img-src 'self' data:",
      "script-src 'self'",
      "style-src 'self' 'unsafe-inline'",
      `connect-src 'self' ${APP_ORIGIN} ${ADMIN_ORIGIN}`
    ].join('; ');
    res.setHeader('Content-Security-Policy', csp);
    res.setHeader('Strict-Transport-Security', 'max-age=63072000; includeSubDomains');
    res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=(), payment=()');
  }catch(_){}
  next();
};
