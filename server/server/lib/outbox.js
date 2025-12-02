const db = require('./db');
const fs = require('fs');
const path = require('path');

const LOG_FILE = path.join(__dirname, '..', '.outbox.log');

function logOutbox(message) {
    const ts = new Date().toISOString();
    fs.appendFileSync(LOG_FILE, `${ts} ${message}\n`);
}

async function enqueue(storeId, eventType, payload) {
    const result = await db.query(
        `INSERT INTO outbox (store_id, event_type, payload, created_at)
         VALUES ($1, $2, $3, NOW())
         RETURNING id`,
        [storeId, eventType, JSON.stringify(payload)]
    );
    logOutbox(`ENQUEUE id=${result.rows[0].id} store=${storeId} type=${eventType}`);
    return result.rows[0].id;
}

async function addEvent(event_type, aggregate_type, aggregate_id, payload = {}, headers = {}) {
  await (db.q || db.query)(
    `INSERT INTO outbox(aggregate_type, aggregate_id, event_type, payload, headers, status, attempts, available_at, created_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING',0, now(), now())`,
    [aggregate_type, aggregate_id, event_type, payload, headers]
  );
}

/** 트랜잭션 내 outbox 적재 (client가 있으면 client.query 사용) */
async function addEventTx(client, event_type, aggregate_type, aggregate_id, payload = {}, headers = {}) {
  const q = client && typeof client.query === 'function'
    ? (sql, params) => client.query(sql, params)
    : (sql, params) => (db.q || db.query)(sql, params);
  await q(
    `INSERT INTO outbox(aggregate_type, aggregate_id, event_type, payload, headers, status, attempts, available_at, created_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING',0, now(), now())`,
    [aggregate_type, aggregate_id, event_type, payload, headers]
  );
}

async function peek(limit = 10) {
    const result = await db.query(
        `SELECT * FROM outbox WHERE processed_at IS NULL ORDER BY created_at LIMIT $1`,
        [limit]
    );
    return result.rows;
}

async function markProcessed(id) {
    await db.query(
        `UPDATE outbox SET processed_at = NOW() WHERE id = $1`,
        [id]
    );
    logOutbox(`PROCESSED id=${id}`);
}

async function flush() {
    const items = await peek(100);
    for (const item of items) {
        try {
            // 실제 처리 로직 (예: 채널 업로드)
            logOutbox(`FLUSH id=${item.id} type=${item.event_type}`);
            await markProcessed(item.id);
        } catch (e) {
            logOutbox(`ERROR id=${item.id} error=${e.message}`);
        }
    }
    return items.length;
}

async function startWorker(intervalMs = 30000) {
    setInterval(async () => {
        try {
            const count = await flush();
            if (count > 0) {
                logOutbox(`WORKER processed ${count} items`);
            }
        } catch (e) {
            logOutbox(`WORKER ERROR: ${e.message}`);
        }
    }, intervalMs);
    logOutbox('WORKER started');
}

function adminRouter() {
    const express = require('express');
    const router = express.Router();
    
    router.get('/peek', async (req, res) => {
        const limit = parseInt(req.query.limit || '10');
        const items = await peek(limit);
        res.json({ ok: true, items, count: items.length });
    });
    
    router.post('/flush', async (req, res) => {
        const count = await flush();
        res.json({ ok: true, processed: count });
    });
    
    router.post('/drain', async (req, res) => {
        let total = 0;
        while (true) {
            const count = await flush();
            if (count === 0) break;
            total += count;
        }
        res.json({ ok: true, processed: total });
    });
    
    return router;
}

module.exports = { enqueue, peek, flush, startWorker, adminRouter, addEvent, addEventTx };
