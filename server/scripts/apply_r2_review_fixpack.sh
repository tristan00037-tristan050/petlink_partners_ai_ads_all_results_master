#!/usr/bin/env bash
# apply_r2_review_fixpack.sh - r2 보완 픽스팩: B1~B5 일괄 적용

set -e

mkdir -p server/{mw,lib,media} scripts

############################################
# B1. 인증 미들웨어 추가 (server/mw/auth.js)
############################################
cat > server/mw/auth.js <<'EOF'
// 간단 HMAC 토큰(JWT 대용). 운영 전환 시 JWT로 교체 권장.
const crypto = require('crypto');

const SIGN = process.env.APP_HMAC || 'dev-hmac-secret';

function b64(o) { return Buffer.from(JSON.stringify(o)).toString('base64url'); }
function signPayload(p) { return crypto.createHmac('sha256', SIGN).update(p).digest('base64url'); }

exports.issue = (storeId, ttlSec = 24 * 60 * 60) => {
    const payload = { sid: Number(storeId), exp: Date.now() + ttlSec * 1000 };
    const p = b64(payload);
    const mac = signPayload(p);
    return `${p}.${mac}`;
};

exports.verify = (tok) => {
    const [p, mac] = String(tok || '').split('.');
    if (!p || !mac) throw new Error('BAD_TOKEN');
    if (signPayload(p) !== mac) throw new Error('BAD_TOKEN_SIG');
    const obj = JSON.parse(Buffer.from(p, 'base64url').toString());
    if (Date.now() > obj.exp) throw new Error('TOKEN_EXPIRED');
    return obj;
};

exports.requireAuth = (publicPaths = []) => (req, res, next) => {
    if (publicPaths.some(prefix => req.path.startsWith(prefix))) return next();
    
    const h = req.header('Authorization') || '';
    const m = h.match(/^Bearer\s+(.+)$/i);
    
    if (!m) return res.status(401).json({ ok: false, error: 'UNAUTHORIZED' });
    
    try {
        const data = exports.verify(m[1]);
        const sid = Number(req.header('X-Store-ID') || 0);
        
        if (!sid || sid !== Number(data.sid)) {
            return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
        }
        
        req.storeId = sid;  // 이후 라우트가 이 값을 사용
        return next();
    } catch (e) {
        return res.status(401).json({ ok: false, error: String(e.message || 'UNAUTHORIZED') });
    }
};
EOF

############################################
# B2. 요청 스키마(zod) 추가 (server/lib/validators.js)
############################################
cat > server/lib/validators.js <<'EOF'
const { z } = require('zod');

exports.prefsSchema = z.object({
    ig_enabled: z.boolean().optional(),
    tt_enabled: z.boolean().optional(),
    yt_enabled: z.boolean().optional(),
    kakao_enabled: z.boolean().optional(),
    naver_enabled: z.boolean().optional(),
});

exports.radiusSchema = z.object({ radius_km: z.number().min(1).max(20) });

exports.weightsSchema = z.object({
    mon: z.number().positive().optional(),
    tue: z.number().positive().optional(),
    wed: z.number().positive().optional(),
    thu: z.number().positive().optional(),
    fri: z.number().positive().optional(),
    sat: z.number().positive().optional(),
    sun: z.number().positive().optional(),
    holiday: z.number().positive().optional(),
    holidays: z.array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).optional()
});

exports.pacerPreviewSchema = z.object({
    store_id: z.number().positive(),
    month: z.string().regex(/^\d{4}-\d{2}$/),
    remaining_budget: z.number().min(0),
    band_pct: z.number().min(0).max(80).optional()
});

exports.pacerApplySchema = z.object({
    store_id: z.number().positive(),
    month: z.string().regex(/^\d{4}-\d{2}$/),
    schedule: z.array(z.object({
        date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        amount: z.number().min(0),
        min: z.number().min(0),
        max: z.number().min(0)
    })).min(1)
});

exports.animalSchema = z.object({
    store_id: z.number().positive(),
    species: z.string().min(1),
    breed: z.string().min(1),
    sex: z.string().min(1),
    age_label: z.string().optional(),
    title: z.string().optional(),
    caption: z.string().optional(),
    note: z.string().optional()
});

exports.draftSchema = z.object({
    store_id: z.number().positive(),
    animal_id: z.number().optional(),
    channels: z.array(z.enum(['META', 'TIKTOK', 'YOUTUBE', 'KAKAO', 'NAVER'])).optional(),
    copy: z.string().min(1)
});

exports.ingestSchema = z.array(z.object({
    ts: z.string().min(1),
    store_id: z.number().optional(),
    impressions: z.number().min(0).optional(),
    views: z.number().min(0).optional(),
    clicks: z.number().min(0).optional(),
    cost: z.number().min(0).optional(),
    conversions: z.object({
        dm: z.number().min(0).optional(),
        call: z.number().min(0).optional(),
        route: z.number().min(0).optional(),
        lead: z.number().min(0).optional(),
    }).optional()
})).max(5000);
EOF

############################################
# B4. CORS 에러 핸들러 추가(Express 에러 미들웨어)
############################################
# app.js 내 '/web' static 등록 직후에 에러핸들러를 주입합니다.
if [ -f server/app.js ]; then
    if ! grep -q "CORS_NOT_ALLOWED" server/app.js; then
        # '/web' static 등록 직후에 에러 핸들러 추가
        perl -0777 -pe 's|(app\.use\(.*\/web.*express\.static.*\))|$1\napp.use((err, req, res, next) => {\n  if (String(err && err.message).includes("CORS_NOT_ALLOWED")) {\n    return res.status(403).json({ ok: false, error: "CORS_NOT_ALLOWED" });\n  }\n  return next(err);\n});|' server/app.js > server/app.js.tmp && mv server/app.js.tmp server/app.js || true
    fi
fi

############################################
# B5. ffmpeg 가용성 체크 강화 (server/media/video_worker.js)
############################################
if [ -f server/media/video_worker.js ]; then
    perl -0777 -pe 's/function hasFfmpeg\(\)[\s\S]*?\{[\s\S]*?\}/function hasFfmpeg(){\n  const {spawnSync} = require('\''child_process'\'');\n  const p = spawnSync('\''ffmpeg'\'',['\''-version'\''], {stdio: '\''ignore'\''});\n  return p.status===0;\n}/g' -i server/media/video_worker.js || true
fi

echo "fixpack done"


