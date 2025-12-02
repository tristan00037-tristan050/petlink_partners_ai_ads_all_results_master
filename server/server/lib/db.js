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

// r4: db.q 별칭 (호환성) - housekeeping.js, payments.js, ads_billing.js, ads_payment_methods.js, admin_quality.js에서 사용
async function q(text, params) {
    return query(text, params);
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

module.exports = { query, q, transaction, getPool };
