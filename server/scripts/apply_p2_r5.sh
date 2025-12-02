#!/usr/bin/env bash
# apply_p2_r5.sh - P2-r5 패치 적용 (Housekeeping, DLQ)

set -euo pipefail

echo "[r5] P2-r5 overlay patch 적용 시작"

mkdir -p server/mw server/lib server/routes/admin

# --- Housekeeping 라우트 ---
cat > server/routes/admin/housekeeping.js <<'JS'
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
JS

# --- app.js에 r5 라우트 추가 (admin 미들웨어 뒤에) ---
if [ -f server/app.js ]; then
    # r5 라우트가 이미 있으면 스킵
    if ! grep -q "admin/ops" server/app.js && ! grep -q "routes/admin/housekeeping" server/app.js; then
        # admin/outbox 라인 뒤에 추가
        if grep -q "admin/outbox" server/app.js; then
            awk '
                /admin\/outbox/ {
                    print
                    print "app.use(\x27/admin/ops\x27, require(\x27./mw/admin\x27).requireAdmin, require(\x27./routes/admin/housekeeping\x27));"
                    next
                }
                { print }
            ' server/app.js > server/app.js.r5 && mv server/app.js.r5 server/app.js
            echo "[r5] admin/ops 라우트 추가 완료"
        else
            # r4 오버레이 블록 뒤에 추가
            if grep -q "r4 오버레이" server/app.js || grep -q "outbox.*startWorker" server/app.js; then
                awk '
                    /outbox.*startWorker/ {
                        print
                        print ""
                        print "// r5 오버레이: Housekeeping, DLQ"
                        print "try {"
                        print "    app.use(\x27/admin/ops\x27, require(\x27./mw/admin\x27).requireAdmin, require(\x27./routes/admin/housekeeping\x27));"
                        print "} catch (e) {"
                        print "    console.warn(\x27[r5] 오버레이 로드 실패 (계속 진행):\x27, e.message);"
                        print "}"
                        next
                    }
                    { print }
                ' server/app.js > server/app.js.r5 && mv server/app.js.r5 server/app.js
                echo "[r5] admin/ops 라우트 추가 완료 (r4 블록 뒤)"
            else
                echo "[r5] [WARN] app.js 구조를 찾을 수 없습니다. 수동으로 추가하세요:"
                echo "app.use('/admin/ops', require('./mw/admin').requireAdmin, require('./routes/admin/housekeeping'));"
            fi
        fi
    else
        echo "[r5] admin/ops 라우트 이미 존재"
    fi
else
    echo "[r5] [ERR] server/app.js 없음"
    exit 1
fi

echo "[r5] P2-r5 overlay patch applied"

