const db = require('../../lib/db');
const express = require('express');
const router = express.Router();

// TTL 만료된 멱등키 정리
async function cleanupExpiredIdempotencyKeys() {
    const { rows } = await db.q(
        `DELETE FROM idempotency_keys 
         WHERE expire_at < NOW() 
         RETURNING key`
    );
    return rows.length;
}

// Outbox DLQ 조회
async function getDLQ(limit = 50) {
    const { rows } = await db.q(
        `SELECT id, event_type, aggregate_type, aggregate_id, payload, attempts, created_at
         FROM outbox
         WHERE status = 'FAILED' AND attempts >= 3
         ORDER BY created_at DESC
         LIMIT $1`,
        [limit]
    );
    return rows;
}

router.post('/housekeeping/run', async (req, res) => {
    try {
        const deleted = await cleanupExpiredIdempotencyKeys();
        res.json({ ok: true, deleted_idempotency_keys: deleted });
    } catch (e) {
        res.status(500).json({ ok: false, error: e.message });
    }
});

router.get('/outbox/dlq', async (req, res) => {
    try {
        const limit = parseInt(req.query.limit || '50', 10);
        const dlq = await getDLQ(limit);
        res.json({ ok: true, dlq, count: dlq.length });
    } catch (e) {
        res.status(500).json({ ok: false, error: e.message });
    }
});

module.exports = router;
