function requireAdmin(req, res, next) {
    const key = req.get('X-Admin-Key') || req.headers['x-admin-key'];
    if (key !== process.env.ADMIN_KEY) {
        return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }
    next();
}

module.exports = { requireAdmin };
