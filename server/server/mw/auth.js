const crypto = require('crypto');

const SIGN = process.env.APP_HMAC || 'dev-secret';
const MAX_AGE = 60 * 60; // 1시간

function b64(s) { return Buffer.from(s).toString('base64url'); }
function ub64(s) { return Buffer.from(s, 'base64url').toString(); }

function sign(obj) {
    const payload = b64(JSON.stringify(obj));
    const mac = crypto.createHmac('sha256', SIGN).update(payload).digest('base64url');
    return payload + "." + mac;
}

function verify(tok) {
    const [p, mac] = tok.split('.');
    const mac2 = crypto.createHmac('sha256', SIGN).update(p).digest('base64url');
    if (mac !== mac2) throw new Error('BAD_TOKEN');
    const obj = JSON.parse(ub64(p));
    if (Date.now() > obj.exp) throw new Error('EXPIRED');
    return obj;
}

function issue(store_id, ttl = MAX_AGE) {
    const now = Date.now();
    return sign({ store_id, iat: now, exp: now + ttl * 1000 });
}

function requireAuth(allowList = []) {
    return (req, res, next) => {
        const open = allowList.some(p => req.path.startsWith(p));
        if (open) return next();
        
        const b = req.headers.authorization || '';
        const sid = Number(req.header('X-Store-ID') || 0);
        
        if (!b.startsWith('Bearer ') || !sid) {
            return res.status(401).json({ ok: false, error: 'UNAUTHORIZED' });
        }
        
        try {
            const t = b.slice(7);
            const payload = verify(t);
            if (payload.store_id !== sid) {
                return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
            }
            req.storeId = sid;
            req.auth = payload;
            next();
        } catch (e) {
            return res.status(401).json({ ok: false, error: String(e.message || 'AUTH_FAIL') });
        }
    };
}

module.exports = { issue, verify, requireAuth, sign };


