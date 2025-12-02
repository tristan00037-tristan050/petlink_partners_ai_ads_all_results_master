#!/usr/bin/env node
// run_sql.js - SQL 파일을 PostgreSQL에 실행 (psql 대체)

const fs = require('fs');
const { Pool } = require('pg');
const path = require('path');

const sqlFile = process.argv[2];

if (!sqlFile) {
    console.error('[ERR] 사용법: node scripts/run_sql.js <sql_file>');
    process.exit(1);
}

if (!fs.existsSync(sqlFile)) {
    console.error(`[ERR] 파일 없음: ${sqlFile}`);
    process.exit(1);
}

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
    console.error('[ERR] DATABASE_URL 환경변수 필요');
    process.exit(1);
}

const pool = new Pool({
    connectionString: DATABASE_URL,
    ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : false
});

async function run() {
    const client = await pool.connect();
    try {
        const sql = fs.readFileSync(sqlFile, 'utf8');
        console.log(`[INFO] SQL 실행: ${sqlFile}`);
        
        // 전체 SQL을 한 번에 실행 (PostgreSQL은 여러 문장을 한 번에 실행 가능)
        try {
            await client.query(sql);
            console.log(`[OK] 마이그레이션 완료: ${sqlFile}`);
        } catch (e) {
            // IF NOT EXISTS 등은 무시
            if (e.message.includes('already exists') || 
                e.message.includes('duplicate') ||
                e.message.includes('does not exist') && e.message.includes('CREATE')) {
                console.log(`[SKIP] ${e.message.split('\n')[0]}`);
            } else {
                // 세미콜론으로 분리하여 재시도
                console.log(`[INFO] 전체 실행 실패, 문장별 실행 시도`);
                const statements = sql
                    .split(/;\s*(?=\n|$)/)
                    .map(s => s.trim())
                    .filter(s => s.length > 0 && !s.match(/^--/));
                
                for (const stmt of statements) {
                    if (stmt.trim() && !stmt.match(/^--/)) {
                        try {
                            await client.query(stmt);
                        } catch (e2) {
                            if (e2.message.includes('already exists') || 
                                e2.message.includes('duplicate') ||
                                (e2.message.includes('does not exist') && e2.message.includes('CREATE'))) {
                                console.log(`[SKIP] ${e2.message.split('\n')[0]}`);
                            } else {
                                console.error(`[ERR] 문장 실행 실패: ${stmt.substring(0, 50)}... - ${e2.message}`);
                                // 계속 진행
                            }
                        }
                    }
                }
            }
        }
    } catch (e) {
        console.error(`[ERR] 마이그레이션 실패: ${e.message}`);
        // 전체 실패 시에도 계속 진행 (이미 존재하는 경우 등)
        if (!e.message.includes('already exists') && !e.message.includes('duplicate')) {
            process.exit(1);
        }
    } finally {
        client.release();
        await pool.end();
    }
}

run().catch(e => {
    console.error('[ERR]', e);
    process.exit(1);
});
