function requireAdmin(req, res, next) {
  const key = req.headers['x-admin-key'] || '';
  if (!key || key !== process.env.ADMIN_API_KEY) {
    return res.status(403).json({ ok:false, code:'FORBIDDEN' });
  }
  next();
}

module.exports = { requireAdmin };

