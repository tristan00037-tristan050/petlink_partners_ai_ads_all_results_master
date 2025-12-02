const crypto = require('crypto');
const db = require('../lib/db');

function hashRequest(req) {
    const body = JSON.stringify(req.body || {});
    const key = `${req.method}:${req.path}:${body}`;
    return crypto.createHash('sha256').update(key).digest('hex');
}

async function getIdempotencyKey(key, storeId) {
    const result = await db.query(
        'SELECT * FROM idempotency_keys WHERE key = $1 AND store_id = $2',
        [key, storeId]
    );
    return result?.rows[0] || null;
}

async function createIdempotencyKey(key, storeId, requestHash, status = 'IN_PROGRESS') {
    const expireAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000); // 14일
    await db.query(
        `INSERT INTO idempotency_keys (key, store_id, request_hash, status, expire_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (key, store_id) DO NOTHING`,
        [key, storeId, requestHash, status, expireAt]
    );
}

async function updateIdempotencyKey(key, storeId, status, response) {
    await db.query(
        `UPDATE idempotency_keys
         SET status = $1, response = $2, completed_at = NOW()
         WHERE key = $3 AND store_id = $4`,
        [status, JSON.stringify(response), key, storeId]
    );
}

function idempotencyMiddleware() {
    return async (req, res, next) => {
        const key = req.header('Idempotency-Key');
        if (!key) return next();
        
        const storeId = req.storeId || 0;
        if (!storeId) return next();
        
        const requestHash = hashRequest(req);
        const existing = await getIdempotencyKey(key, storeId);
        
        if (existing) {
            if (existing.request_hash !== requestHash) {
                return res.status(409).json({
                    ok: false,
                    error: 'IDEMPOTENCY_KEY_REPLAY_MISMATCH',
                    message: '동일 키로 다른 요청을 재시도했습니다.'
                });
            }
            
            if (existing.status === 'IN_PROGRESS') {
                return res.status(409).json({
                    ok: false,
                    error: 'IDEMPOTENCY_IN_PROGRESS',
                    message: '선행 요청이 처리 중입니다.'
                });
            }
            
            if (existing.status === 'COMPLETED') {
                const savedResponse = JSON.parse(existing.response || '{}');
                res.setHeader('X-Idempotent-Replay', 'true');
                return res.status(existing.status_code || 200).json(savedResponse);
            }
        } else {
            await createIdempotencyKey(key, storeId, requestHash, 'IN_PROGRESS');
        }
        
        // 응답 캡처
        const originalJson = res.json.bind(res);
        res.json = function(data) {
            updateIdempotencyKey(key, storeId, 'COMPLETED', data).catch(console.error);
            originalJson(data);
        };
        
        next();
    };
}

module.exports = idempotencyMiddleware;
