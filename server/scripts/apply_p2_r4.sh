#!/usr/bin/env bash
# apply_p2_r4.sh - P2-r4 오버레이 패치 적용

set -e

mkdir -p server/{mw,lib,openapi} scripts/migrations

# 멱등성 미들웨어
cat > server/mw/idempotency.js <<'EOF'
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
EOF

# Outbox 라이브러리
cat > server/lib/outbox.js <<'EOF'
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

module.exports = { enqueue, peek, flush, startWorker, adminRouter };
EOF

# OpenAPI 스펙 (간단 버전)
cat > server/openapi/petlink.yaml <<'EOF'
openapi: 3.0.0
info:
  title: PetLink Partners API
  version: 2.9.0
  description: PetLink Partners 광고 플랫폼 API

servers:
  - url: http://localhost:5902
    description: 로컬 개발 서버

paths:
  /health:
    get:
      summary: 헬스체크
      responses:
        '200':
          description: 서버 정상
          content:
            application/json:
              schema:
                type: object
                properties:
                  ok:
                    type: boolean
                  ts:
                    type: string

  /auth/signup:
    post:
      summary: 가입 및 토큰 발급
      responses:
        '200':
          description: 성공
          content:
            application/json:
              schema:
                type: object
                properties:
                  ok:
                    type: boolean
                  store_id:
                    type: integer
                  token:
                    type: string

  /stores/{id}/channel-prefs:
    get:
      summary: 채널 설정 조회
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
      security:
        - BearerAuth: []
      responses:
        '200':
          description: 성공
    put:
      summary: 채널 설정 저장
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
      security:
        - BearerAuth: []
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                ig_enabled:
                  type: boolean
                tt_enabled:
                  type: boolean
      responses:
        '200':
          description: 성공

  /organic/drafts:
    post:
      summary: 초안 생성
      security:
        - BearerAuth: []
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required:
                - store_id
                - copy
              properties:
                store_id:
                  type: integer
                copy:
                  type: string
                channels:
                  type: array
                  items:
                    type: string
      responses:
        '201':
          description: 생성됨

  /billing/checkout:
    post:
      summary: 결제
      security:
        - BearerAuth: []
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                plan:
                  type: string
                price:
                  type: integer
      responses:
        '200':
          description: 성공

securitySchemes:
  BearerAuth:
    type: http
    scheme: bearer
    bearerFormat: JWT
EOF

# OpenAPI UI (Swagger UI)
cat > server/openapi/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>PetLink Partners API Docs</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui.css" />
    <style>
        html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
        *, *:before, *:after { box-sizing: inherit; }
        body { margin:0; background: #fafafa; }
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5.9.0/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            const ui = SwaggerUIBundle({
                url: "/openapi.yaml",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
        };
    </script>
</body>
</html>
EOF

echo "P2-r4 overlay patch applied"


