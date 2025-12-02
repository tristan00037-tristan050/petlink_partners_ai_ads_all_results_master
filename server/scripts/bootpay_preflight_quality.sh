#!/usr/bin/env bash
set -euo pipefail
mkdir -p scripts server/routes server/openapi scripts/migrations

# ===== 공통 ENV =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export TIMEZONE="${TIMEZONE:-Asia/Seoul}"
export APP_HMAC="${APP_HMAC:-your-hmac-secret}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:5902,http://localhost:8000}"
export PORT="${PORT:-5902}"

# 스코프 잠금(검토팀 정책)
export ENABLE_CONSUMER_BILLING="false"
export ENABLE_ADS_BILLING="true"

# Billing 모드(샌드박스 유지)
export BILLING_MODE="${BILLING_MODE:-sandbox}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }

# ===== 1) Core‑AI 품질 지표 DDL(없을 때만 추가) =====
cat > scripts/migrations/20251112_ai_quality.sql <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_creatives') THEN
    CREATE TABLE ad_creatives(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER,
      channel TEXT,                              -- META/YOUTUBE/KAKAO/NAVER
      flags JSONB DEFAULT '{}'::jsonb,           -- {"forbidden_count":int,"reject_reasons":[...]}
      format_ok BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMPTZ DEFAULT now(),
      reviewed_at TIMESTAMPTZ,
      approved_at TIMESTAMPTZ
    );
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_ch ON ad_creatives(channel);
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_cre ON ad_creatives(created_at);
  ELSE
    BEGIN
      ALTER TABLE ad_creatives ADD COLUMN IF NOT EXISTS channel TEXT;
      ALTER TABLE ad_creatives ADD COLUMN IF NOT EXISTS format_ok BOOLEAN DEFAULT TRUE;
      ALTER TABLE ad_creatives ADD COLUMN IF NOT EXISTS flags JSONB DEFAULT '{}'::jsonb;
    EXCEPTION WHEN duplicate_column THEN
      -- no-op
    END;
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_ch ON ad_creatives(channel);
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_cre ON ad_creatives(created_at);
  END IF;
END$$;
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251112_ai_quality.sql

# ===== 2) 품질 리포트 API/UI =====
cat > server/routes/admin_quality.js <<'JS'
const express = require('express');
const db = require('../lib/db');
const admin = require('../mw/admin');

const r = express.Router();

/** GET /admin/reports/quality.json?days=7 */
r.get('/quality.json', admin.requireAdmin, async (req,res)=>{
  const days = Math.max(1, Math.min(90, parseInt(req.query.days||'7',10)));
  const params = [days];

  const chq = await db.q(`
    WITH base AS (
      SELECT channel,
             COALESCE((flags->>'forbidden_count')::int,0) AS forb,
             CASE WHEN format_ok THEN 1 ELSE 0 END AS fmt
      FROM ad_creatives
      WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT channel,
           count(*) AS total,
           COALESCE(ROUND(AVG(fmt)::numeric, 4), 0) AS format_rate,
           COALESCE(SUM(forb), 0) AS forb_sum
    FROM base
    GROUP BY channel
    ORDER BY channel NULLS LAST
  `, params);

  const rej = await db.q(`
    WITH src AS (
      SELECT jsonb_array_elements_text(COALESCE(flags->'reject_reasons', '[]'::jsonb)) AS reason
      FROM ad_creatives
      WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT reason, count(*) AS cnt
    FROM src
    GROUP BY reason
    ORDER BY cnt DESC NULLS LAST
    LIMIT 10
  `, params);

  res.json({ ok:true, days, channels: chq.rows, top_reject_reasons: rej.rows });
});

/** GET /admin/reports/quality (HTML) */
r.get('/quality', admin.requireAdmin, async (req,res)=>{
  const chq = await db.q(`
    WITH base AS (
      SELECT channel,
             COALESCE((flags->>'forbidden_count')::int,0) AS forb,
             CASE WHEN format_ok THEN 1 ELSE 0 END AS fmt
      FROM ad_creatives
      WHERE created_at >= now() - interval '7 days'
    )
    SELECT channel, count(*) AS total,
           COALESCE(ROUND(AVG(fmt)::numeric, 4), 0) AS format_rate,
           COALESCE(SUM(forb), 0) AS forb_sum
    FROM base
    GROUP BY channel
    ORDER BY channel NULLS LAST
  `);
  const rej = await db.q(`
    WITH src AS (
      SELECT jsonb_array_elements_text(COALESCE(flags->'reject_reasons','[]'::jsonb)) AS reason
      FROM ad_creatives
      WHERE created_at >= now() - interval '7 days'
    )
    SELECT reason, count(*) AS cnt FROM src
    GROUP BY reason ORDER BY cnt DESC NULLS LAST LIMIT 10
  `);

  const H=(l,v)=>`<div style="border:1px solid #ddd;border-radius:6px;padding:12px;margin:8px;display:inline-block;min-width:220px">
    <div style="font-size:12px;color:#666">${l}</div><div style="font-size:22px;font-weight:700">${v}</div></div>`;
  const pct=(x)=> (Math.round((Number(x||0)*10000))/100)+'%';
  const rows = chq.rows.map(r =>
    `<tr><td>${r.channel||'-'}</td><td>${r.total}</td><td>${pct(r.format_rate)}</td><td>${r.forb_sum}</td></tr>`
  ).join('');
  const rejRows = rej.rows.map(r=>`<tr><td>${r.reason||'-'}</td><td>${r.cnt}</td></tr>`).join('');

  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>AI Quality Report</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2>AI 품질 리포트(최근 7일)</h2>
    <h3>채널별 지표</h3>
    <table border="1" cellspacing="0" cellpadding="6">
      <thead><tr><th>채널</th><th>총 건수</th><th>포맷 적합률</th><th>금칙어 합계</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="4">데이터 없음</td></tr>'}</tbody>
    </table>
    <h3>리젝 Top-10</h3>
    <table border="1" cellspacing="0" cellpadding="6">
      <thead><tr><th>사유</th><th>건수</th></tr></thead>
      <tbody>${rejRows || '<tr><td colspan="2">데이터 없음</td></tr>'}</tbody>
    </table>
  </div>`);
});

module.exports = r;
JS

# ===== 3) Bootpay 실서버 전환 사전 체크(샌드박스에서만 진단) =====
cat > server/routes/admin_bootpay_preflight.js <<'JS'
const express = require('express');
const admin = require('../mw/admin');
const r = express.Router();

r.get('/preflight', admin.requireAdmin, (req,res)=>{
  const adapter = (process.env.BILLING_ADAPTER||'mock').toLowerCase();
  const mode = (process.env.BILLING_MODE||'sandbox').toLowerCase();
  const hasKeys = !!(process.env.BOOTPAY_APP_ID && process.env.BOOTPAY_PRIVATE_KEY);
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING === 'false' && process.env.ENABLE_ADS_BILLING === 'true';
  const ready = (mode === 'sandbox') && scopeLocked;
  res.json({ ok:true, ready, adapter, mode, has_bootpay_keys: hasKeys, scope_locked: scopeLocked });
});
module.exports = r;
JS

# ===== 4) OpenAPI 등록 =====
cat > server/openapi/quality.yaml <<'YAML'
openapi: 3.0.3
info: { title: AI Quality API, version: "g2" }
paths:
  /admin/reports/quality.json: { get: { summary: Quality metrics JSON, responses: { '200': { description: OK } } } }
  /admin/reports/quality:     { get: { summary: Quality metrics HTML, responses: { '200': { description: OK } } } }
  /admin/ads/billing/preflight:
    get: { summary: Bootpay preflight (sandbox only), responses: { '200': { description: OK } } }
YAML

# ===== 5) app.js 장착 =====
if ! grep -q "routes/admin_quality" server/app.js; then
  # express.json() 이후에 라우트 추가
  sed -i.bak '/app\.use(express\.json/i\
app.use('\''/admin/reports'\'', require('\''./routes/admin_quality'\''));\
app.get('\''/openapi_quality.yaml'\'',(req,res)=>res.sendFile(require('\''path'\'').join(__dirname,'\''openapi'\'','\''quality.yaml'\'')));\
' server/app.js && rm -f server/app.js.bak || true
fi

if ! grep -q "routes/admin_bootpay_preflight" server/app.js; then
  # ads/billing 라우트 근처에 추가
  if grep -q "/admin/ads/billing" server/app.js; then
    sed -i.bak '/\/admin\/ads\/billing/a\
app.use('\''/admin/ads/billing'\'', require('\''./routes/admin_bootpay_preflight'\''));\
' server/app.js && rm -f server/app.js.bak || true
  else
    sed -i.bak '/app\.use(express\.json/i\
app.use('\''/admin/ads/billing'\'', require('\''./routes/admin_bootpay_preflight'\''));\
' server/app.js && rm -f server/app.js.bak || true
  fi
fi

# ===== 6) 서버 재기동 =====
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done

# ===== 7) 스모크 =====
curl -sf "http://localhost:${PORT}/admin/ads/billing/preflight" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ok":true' && echo "BOOTPAY PREFLIGHT OK"

curl -sf "http://localhost:${PORT}/admin/reports/quality.json" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ok":true' && echo "QUALITY METRICS OK"

curl -sf "http://localhost:${PORT}/admin/reports/quality" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null \
  && echo "QUALITY UI OK"

curl -sf "http://localhost:${PORT}/openapi_quality.yaml" | head -n1 | grep -q "openapi:" && echo "QUALITY OPENAPI OK"

echo
echo "[DONE] Preflight + AI 품질 지표 확장 집행 완료"
echo "로그 확인: tail -n 200 .petlink.out"


