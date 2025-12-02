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
