#!/usr/bin/env bash
# apply_p2_r3_persistence.sh - P2-r3 영속화 패치 적용

set -e

mkdir -p server/{lib,mw} scripts db/migrations

# DB 연결 라이브러리
cat > server/lib/db.js <<'EOF'
const { Pool } = require('pg');

let pool = null;

function getPool() {
    if (!pool && process.env.DATABASE_URL) {
        pool = new Pool({
            connectionString: process.env.DATABASE_URL,
            ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : false
        });
    }
    return pool;
}

async function query(text, params) {
    const p = getPool();
    if (!p) return null; // DB 없으면 null 반환 (메모리 모드)
    return p.query(text, params);
}

async function transaction(callback) {
    const p = getPool();
    if (!p) return callback(null); // DB 없으면 트랜잭션 없이 실행
    const client = await p.connect();
    try {
        await client.query('BEGIN');
        const result = await callback(client);
        await client.query('COMMIT');
        return result;
    } catch (e) {
        await client.query('ROLLBACK');
        throw e;
    } finally {
        client.release();
    }
}

module.exports = { query, transaction, getPool };
EOF

# 리포지토리 레이어
cat > server/lib/repo.js <<'EOF'
const db = require('./db');
const { DateTime } = require('luxon');

// 스토어
async function getStore(id) {
    const result = await db.query('SELECT * FROM stores WHERE id = $1', [id]);
    return result?.rows[0] || null;
}

async function upsertStore(id, data) {
    const { prefs, radius_km, weights, tz } = data;
    await db.query(
        `INSERT INTO stores (id, prefs, radius_km, weights, tz, updated_at)
         VALUES ($1, $2, $3, $4, $5, NOW())
         ON CONFLICT (id) DO UPDATE
         SET prefs = $2, radius_km = $3, weights = $4, tz = $5, updated_at = NOW()`,
        [id, JSON.stringify(prefs), radius_km, JSON.stringify(weights), tz || 'Asia/Seoul']
    );
}

// 일일 지출
async function addSpend(store_id, date, cost) {
    await db.query(
        `INSERT INTO spend_daily (store_id, date, cost)
         VALUES ($1, $2, $3)
         ON CONFLICT (store_id, date) DO UPDATE
         SET cost = spend_daily.cost + $3`,
        [store_id, date, cost]
    );
}

async function getSpend(store_id, date) {
    const result = await db.query(
        'SELECT cost FROM spend_daily WHERE store_id = $1 AND date = $2',
        [store_id, date]
    );
    return result?.rows[0]?.cost || 0;
}

// 스케줄
async function getSchedule(store_id, month) {
    const result = await db.query(
        'SELECT * FROM schedules WHERE store_id = $1 AND ym = $2 ORDER BY date',
        [store_id, month]
    );
    return result?.rows || [];
}

async function upsertSchedule(store_id, month, schedule) {
    await db.transaction(async (client) => {
        for (const day of schedule) {
            await client.query(
                `INSERT INTO schedules (store_id, ym, date, amount, min, max)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (store_id, date) DO UPDATE
                 SET amount = $4, min = $5, max = $6`,
                [store_id, month, day.date, day.amount, day.min, day.max]
            );
        }
    });
}

// 초안
async function getDraft(id) {
    const result = await db.query('SELECT * FROM drafts WHERE id = $1', [id]);
    return result?.rows[0] || null;
}

async function createDraft(data) {
    const { store_id, animal_id, copy, channels, status } = data;
    const result = await db.query(
        `INSERT INTO drafts (store_id, animal_id, copy, channels, status, history)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [store_id, animal_id, copy, channels, status || 'DRAFT', JSON.stringify([])]
    );
    return result?.rows[0]?.id;
}

async function updateDraft(id, updates) {
    const { status, history, published_at, results } = updates;
    const updates_list = [];
    const params = [];
    let param_idx = 1;
    
    if (status) {
        updates_list.push(`status = $${param_idx++}`);
        params.push(status);
    }
    if (history) {
        updates_list.push(`history = $${param_idx++}`);
        params.push(JSON.stringify(history));
    }
    if (published_at) {
        updates_list.push(`published_at = $${param_idx++}`);
        params.push(published_at);
    }
    if (results) {
        updates_list.push(`results = $${param_idx++}`);
        params.push(JSON.stringify(results));
    }
    
    if (updates_list.length === 0) return;
    
    updates_list.push(`updated_at = NOW()`);
    params.push(id);
    
    await db.query(
        `UPDATE drafts SET ${updates_list.join(', ')} WHERE id = $${param_idx}`,
        params
    );
}

// 승인 토큰
async function createApprovalToken(draft_id, channel, exp_at) {
    const result = await db.query(
        `INSERT INTO approval_tokens (draft_id, channel, exp_at)
         VALUES ($1, $2, $3)
         RETURNING jti`,
        [draft_id, channel, exp_at]
    );
    return result?.rows[0]?.jti;
}

async function useApprovalToken(jti) {
    const result = await db.query(
        `UPDATE approval_tokens SET used_at = NOW() WHERE jti = $1 AND used_at IS NULL RETURNING *`,
        [jti]
    );
    return result?.rows[0] || null;
}

// 감사 로그
async function auditLog(store_id, type, payload) {
    await db.query(
        `INSERT INTO audit (store_id, type, payload) VALUES ($1, $2, $3)`,
        [store_id, type, JSON.stringify(payload)]
    );
}

module.exports = {
    getStore, upsertStore,
    addSpend, getSpend,
    getSchedule, upsertSchedule,
    getDraft, createDraft, updateDraft,
    createApprovalToken, useApprovalToken,
    auditLog
};
EOF

# 시간 유틸리티
cat > server/lib/time.js <<'EOF'
const { DateTime } = require('luxon');

const TZ = process.env.TIMEZONE || 'Asia/Seoul';

function today() {
    return DateTime.now().setZone(TZ).toISODate();
}

function now() {
    return DateTime.now().setZone(TZ).toISO();
}

function parseDate(dateStr) {
    return DateTime.fromISO(dateStr, { zone: TZ });
}

module.exports = { today, now, parseDate, TZ };
EOF

# 관리자 미들웨어
cat > server/mw/admin.js <<'EOF'
function requireAdmin(req, res, next) {
    const key = req.header('X-Admin-Key');
    if (key !== process.env.ADMIN_KEY) {
        return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }
    next();
}

module.exports = { requireAdmin };
EOF

# 감사 로그 라이브러리
cat > server/lib/audit.js <<'EOF'
const repo = require('./repo');

async function log(store_id, type, payload) {
    try {
        await repo.auditLog(store_id, type, payload);
    } catch (e) {
        console.error('Audit log error:', e);
    }
}

module.exports = { log };
EOF

echo "P2-r3 persistence patch applied"


