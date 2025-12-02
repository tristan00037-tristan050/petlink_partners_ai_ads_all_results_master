#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/routes server/lib

export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need curl; need psql
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }

# =====================================================================================
# [1] advertiser_profile 테이블 생성
# =====================================================================================
cat > scripts/migrations/20251113_advertiser_profile.sql <<'SQL'
CREATE TABLE IF NOT EXISTS advertiser_profile (
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL UNIQUE,
  store_name TEXT,
  business_number TEXT,
  address TEXT,
  phone TEXT,
  email TEXT,
  website TEXT,
  description TEXT,
  logo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_advertiser_profile_adv_id ON advertiser_profile(advertiser_id);
SQL

node scripts/run_sql.js scripts/migrations/20251113_advertiser_profile.sql >/dev/null
echo "ADVERTISER PROFILE TABLE OK"

# =====================================================================================
# [2] POST /ads/validate 라우트 구현
# =====================================================================================
cat > server/routes/ads_validate.js <<'JS'
const express = require('express');
const db = require('../lib/db');
const fs = require('fs');
const path = require('path');
const r = express.Router();

// 금칙어 로드
let bannedWords = [];
try {
  const banwordsPath = path.join(__dirname, '../../config/banwords_ko.txt');
  if (fs.existsSync(banwordsPath)) {
    bannedWords = fs.readFileSync(banwordsPath, 'utf8')
      .split('\n')
      .map(w => w.trim())
      .filter(w => w && !w.startsWith('#'));
  }
} catch (e) {
  console.warn('[validate] banwords load failed:', e.message);
}

// 금지 키워드 패턴 로드
let bannedPatterns = {};
try {
  const bannedPath = path.join(__dirname, '../../policy/banned_keywords.json');
  if (fs.existsSync(bannedPath)) {
    const banned = JSON.parse(fs.readFileSync(bannedPath, 'utf8'));
    bannedPatterns = banned.categories || {};
  }
} catch (e) {
  console.warn('[validate] banned_keywords load failed:', e.message);
}

// 채널별 길이 제한
const CHANNEL_LIMITS = {
  META: { text: 125, hashtags: 30, links: 1 },
  YOUTUBE: { text: 100, hashtags: 0, links: 1 },
  KAKAO: { text: 200, hashtags: 0, links: 0 },
  NAVER: { text: 150, hashtags: 10, links: 1 }
};

// 텍스트 길이 검증
function validateLength(text, channel) {
  const limit = CHANNEL_LIMITS[channel]?.text || 200;
  if (text.length > limit) {
    return {
      type: 'LENGTH',
      severity: 'error',
      message: `텍스트가 ${limit}자 제한을 초과했습니다 (${text.length}자)`,
      limit,
      actual: text.length
    };
  }
  return null;
}

// 금칙어 검사
function validateBannedWords(text) {
  const issues = [];
  const lowerText = text.toLowerCase();
  
  for (const word of bannedWords) {
    if (word && lowerText.includes(word.toLowerCase())) {
      const pos = lowerText.indexOf(word.toLowerCase());
      issues.push({
        type: 'BANNED_WORD',
        severity: 'error',
        word,
        position: pos,
        message: `금칙어 "${word}" 발견`
      });
    }
  }
  
  return issues;
}

// 금지 패턴 검사
function validateBannedPatterns(text) {
  const issues = [];
  
  for (const [category, rules] of Object.entries(bannedPatterns)) {
    if (!rules.keywords && !rules.patterns) continue;
    
    // 키워드 검사
    if (rules.keywords) {
      for (const keyword of rules.keywords) {
        if (text.includes(keyword)) {
          issues.push({
            type: 'BANNED_PATTERN',
            severity: 'warn',
            category,
            keyword,
            message: `${rules.description || category} 관련 표현 "${keyword}" 발견`
          });
        }
      }
    }
    
    // 패턴 검사
    if (rules.patterns) {
      for (const pattern of rules.patterns) {
        try {
          const regex = new RegExp(pattern, 'gi');
          if (regex.test(text)) {
            issues.push({
              type: 'BANNED_PATTERN',
              severity: 'warn',
              category,
              pattern,
              message: `${rules.description || category} 관련 패턴 발견`
            });
          }
        } catch (e) {
          // 잘못된 정규식 무시
        }
      }
    }
  }
  
  return issues;
}

// 해시태그 검증
function validateHashtags(hashtags, channel) {
  const issues = [];
  const limit = CHANNEL_LIMITS[channel]?.hashtags || 0;
  
  if (hashtags.length > limit) {
    issues.push({
      type: 'HASHTAG_LIMIT',
      severity: 'error',
      message: `해시태그가 ${limit}개 제한을 초과했습니다 (${hashtags.length}개)`,
      limit,
      actual: hashtags.length
    });
  }
  
  // 해시태그 형식 검증
  for (let i = 0; i < hashtags.length; i++) {
    const tag = hashtags[i];
    if (!tag.startsWith('#')) {
      issues.push({
        type: 'HASHTAG_FORMAT',
        severity: 'error',
        message: `해시태그 "${tag}"는 #으로 시작해야 합니다`,
        tag,
        index: i
      });
    }
    if (tag.length > 30) {
      issues.push({
        type: 'HASHTAG_LENGTH',
        severity: 'warn',
        message: `해시태그 "${tag}"가 너무 깁니다 (30자 제한)`,
        tag,
        length: tag.length
      });
    }
  }
  
  return issues;
}

// 링크 검증
function validateLinks(links, channel) {
  const issues = [];
  const limit = CHANNEL_LIMITS[channel]?.links || 0;
  
  if (links.length > limit) {
    issues.push({
      type: 'LINK_LIMIT',
      severity: 'error',
      message: `링크가 ${limit}개 제한을 초과했습니다 (${links.length}개)`,
      limit,
      actual: links.length
    });
  }
  
  // URL 형식 검증
  const urlPattern = /^https?:\/\/.+/;
  for (let i = 0; i < links.length; i++) {
    const link = links[i];
    if (!urlPattern.test(link)) {
      issues.push({
        type: 'LINK_FORMAT',
        severity: 'error',
        message: `링크 "${link}"가 올바른 URL 형식이 아닙니다`,
        link,
        index: i
      });
    }
  }
  
  return issues;
}

// 점수 계산 (0.0 ~ 1.0)
function calculateScore(issues) {
  const errorCount = issues.filter(i => i.severity === 'error').length;
  const warnCount = issues.filter(i => i.severity === 'warn').length;
  
  // 에러 1개당 -0.3, 경고 1개당 -0.1
  const score = Math.max(0, 1.0 - (errorCount * 0.3) - (warnCount * 0.1));
  return Math.round(score * 100) / 100;
}

/** POST /ads/validate */
r.post('/validate', express.json(), async (req, res) => {
  try {
    const { advertiser_id, channel, text, hashtags = [], links = [] } = req.body || {};
    
    if (!advertiser_id || !channel || !text) {
      return res.status(400).json({ ok: false, code: 'FIELDS_REQUIRED' });
    }
    
    if (!CHANNEL_LIMITS[channel]) {
      return res.status(400).json({ ok: false, code: 'INVALID_CHANNEL', channels: Object.keys(CHANNEL_LIMITS) });
    }
    
    const issues = [];
    
    // 길이 검증
    const lengthIssue = validateLength(text, channel);
    if (lengthIssue) issues.push(lengthIssue);
    
    // 금칙어 검사
    issues.push(...validateBannedWords(text));
    
    // 금지 패턴 검사
    issues.push(...validateBannedPatterns(text));
    
    // 해시태그 검증
    if (hashtags.length > 0) {
      issues.push(...validateHashtags(hashtags, channel));
    }
    
    // 링크 검증
    if (links.length > 0) {
      issues.push(...validateLinks(links, channel));
    }
    
    const score = calculateScore(issues);
    const valid = issues.filter(i => i.severity === 'error').length === 0;
    
    res.json({
      ok: true,
      valid,
      score,
      issues,
      channel,
      summary: {
        total_issues: issues.length,
        errors: issues.filter(i => i.severity === 'error').length,
        warnings: issues.filter(i => i.severity === 'warn').length
      }
    });
  } catch (e) {
    console.error('[validate] error:', e);
    res.status(500).json({ ok: false, code: 'VALIDATION_ERROR', error: String(e.message || e) });
  }
});

module.exports = r;
JS

# =====================================================================================
# [3] GET/PUT /advertiser/profile 라우트 구현
# =====================================================================================
cat > server/routes/advertiser_profile.js <<'JS'
const express = require('express');
const db = require('../lib/db');
const r = express.Router();

/** GET /advertiser/profile?advertiser_id=101 */
r.get('/profile', async (req, res) => {
  try {
    const advertiser_id = parseInt(req.query.advertiser_id, 10);
    if (!advertiser_id) {
      return res.status(400).json({ ok: false, code: 'ADVERTISER_ID_REQUIRED' });
    }
    
    const q = await db.q(
      `SELECT * FROM advertiser_profile WHERE advertiser_id=$1 LIMIT 1`,
      [advertiser_id]
    );
    
    if (q.rows.length === 0) {
      return res.json({ ok: true, profile: null });
    }
    
    res.json({ ok: true, profile: q.rows[0] });
  } catch (e) {
    console.error('[profile] GET error:', e);
    res.status(500).json({ ok: false, code: 'PROFILE_GET_ERROR', error: String(e.message || e) });
  }
});

/** PUT /advertiser/profile */
r.put('/profile', express.json(), async (req, res) => {
  try {
    const { advertiser_id, store_name, business_number, address, phone, email, website, description, logo_url } = req.body || {};
    
    if (!advertiser_id) {
      return res.status(400).json({ ok: false, code: 'ADVERTISER_ID_REQUIRED' });
    }
    
    await db.q(`
      INSERT INTO advertiser_profile (
        advertiser_id, store_name, business_number, address, phone, email, website, description, logo_url, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
      ON CONFLICT (advertiser_id) DO UPDATE SET
        store_name = EXCLUDED.store_name,
        business_number = EXCLUDED.business_number,
        address = EXCLUDED.address,
        phone = EXCLUDED.phone,
        email = EXCLUDED.email,
        website = EXCLUDED.website,
        description = EXCLUDED.description,
        logo_url = EXCLUDED.logo_url,
        updated_at = now()
    `, [advertiser_id, store_name || null, business_number || null, address || null, phone || null, email || null, website || null, description || null, logo_url || null]);
    
    const q = await db.q(
      `SELECT * FROM advertiser_profile WHERE advertiser_id=$1 LIMIT 1`,
      [advertiser_id]
    );
    
    res.json({ ok: true, profile: q.rows[0] });
  } catch (e) {
    console.error('[profile] PUT error:', e);
    res.status(500).json({ ok: false, code: 'PROFILE_UPDATE_ERROR', error: String(e.message || e) });
  }
});

module.exports = r;
JS

# =====================================================================================
# [4] app.js에 라우트 마운트
# =====================================================================================
if ! grep -q "routes/ads_validate" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/ads', require('./routes/ads_validate'));\\
" server/app.js && rm -f server/app.js.bak
fi

if ! grep -q "routes/advertiser_profile" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/advertiser', require('./routes/advertiser_profile'));\\
" server/app.js && rm -f server/app.js.bak
fi

echo "ROUTES MOUNTED OK"

# =====================================================================================
# [5] 서버 재기동
# =====================================================================================
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 2
curl -sf "http://localhost:${PORT}/health" >/dev/null || { echo "[ERR] server not healthy"; exit 1; }

# =====================================================================================
# [6] 스모크 테스트
# =====================================================================================
echo "=== 스모크 테스트 ==="

# 1) POST /ads/validate - 정상 케이스
RESP1=$(curl -sf -XPOST "http://localhost:${PORT}/ads/validate" \
  -H "Content-Type: application/json" \
  -d '{"advertiser_id":101,"channel":"META","text":"멋진 반려동물을 만나보세요","hashtags":["#반려동물","#펫"],"links":["https://example.com"]}')
echo "$RESP1" | grep -q '"ok":true' && echo "VALIDATE OK" || echo "VALIDATE FAIL"

# 2) POST /ads/validate - 에러 케이스 (길이 초과)
RESP2=$(curl -sf -XPOST "http://localhost:${PORT}/ads/validate" \
  -H "Content-Type: application/json" \
  -d '{"advertiser_id":101,"channel":"META","text":"'$(python3 -c "print('A'*200)")'","hashtags":[],"links":[]}')
echo "$RESP2" | grep -q '"valid":false' && echo "VALIDATE ERROR CASE OK" || echo "VALIDATE ERROR CASE FAIL"

# 3) PUT /advertiser/profile
RESP3=$(curl -sf -XPUT "http://localhost:${PORT}/advertiser/profile" \
  -H "Content-Type: application/json" \
  -d '{"advertiser_id":101,"store_name":"테스트 매장","business_number":"123-45-67890","phone":"010-1234-5678","email":"test@example.com"}')
echo "$RESP3" | grep -q '"ok":true' && echo "PROFILE PUT OK" || echo "PROFILE PUT FAIL"

# 4) GET /advertiser/profile
RESP4=$(curl -sf "http://localhost:${PORT}/advertiser/profile?advertiser_id=101")
echo "$RESP4" | grep -q '"ok":true' && echo "PROFILE GET OK" || echo "PROFILE GET FAIL"

echo "WEBAPP P0 DONE"

