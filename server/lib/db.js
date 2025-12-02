/**
 * P0: 데이터베이스 연결 유틸리티
 * PostgreSQL 연결 풀 관리
 */

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:petpass@localhost:5432/petlink',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

/**
 * 쿼리 실행
 */
async function q(text, params) {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;
    
    // 성능 로깅 (200ms 이상인 경우)
    if (duration > 200) {
      console.warn(`[DB Slow Query] ${duration}ms: ${text.substring(0, 100)}`);
    }
    
    return result;
  } catch (error) {
    console.error('[DB Error]', error.message, text.substring(0, 100));
    throw error;
  }
}

/**
 * 트랜잭션 실행
 */
async function transaction(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  q,
  transaction,
  pool
};

