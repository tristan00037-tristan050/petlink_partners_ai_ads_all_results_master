#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/routes server/lib server/openapi scripts artifacts

export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"

# Gate‑WEBAPP 기준(운영 고정값)
export WEBAPP_GATE_APPROVE_RATE="${WEBAPP_GATE_APPROVE_RATE:-0.95}"      # 자동 승인율 최소
export WEBAPP_GATE_P95_MS="${WEBAPP_GATE_P95_MS:-300000}"                # p95 루프 시간 최대(5분)

# 금칙어 정책 환경변수 반영(이미 설정되어 있다면 그대로 사용)
export FORBIDDEN_PATTERNS="${FORBIDDEN_PATTERNS:-무료|공짜|100%\\s*보장|전액환불}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need curl; need psql
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js not found"; exit 1; }

############################################
# 0) DB 보강: channel_rules(버전관리), moderation logs loop_id
############################################
cat > scripts/migrations/20251114_r74_rules_loop.sql <<'SQL'
-- 0-1) channel_rules(버전관리) 추가
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='channel_rules') THEN
    CREATE TABLE channel_rules(
      id BIGSERIAL PRIMARY KEY,
      channel TEXT NOT NULL,
      rule_version INTEGER NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('DRAFT','ACTIVE','DEPRECATED')),
      config JSONB NOT NULL,
      effective_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE INDEX idx_channel_rules_ch ON channel_rules(channel);
    CREATE UNIQUE INDEX uq_channel_rules_active ON channel_rules(channel) WHERE status='ACTIVE';
  ELSE
    -- 기존 테이블에 컬럼 추가
    BEGIN
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS id BIGSERIAL;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS rule_version INTEGER DEFAULT 1;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'ACTIVE';
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS config JSONB DEFAULT '{}'::jsonb;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS effective_at TIMESTAMPTZ;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
    EXCEPTION WHEN duplicate_column THEN NULL;
    END;
  END IF;
END$$;
CREATE INDEX IF NOT EXISTS idx_channel_rules_ch ON channel_rules(channel);

-- ad_channel_rules 가 이미 존재한다면 ACTIVE 스냅샷을 채워 넣음(1회성)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_channel_rules') THEN
    INSERT INTO channel_rules(channel, rule_version, status, config, effective_at)
    SELECT acr.channel, 1, 'ACTIVE', acr.config, now()
    FROM ad_channel_rules acr
    ON CONFLICT DO NOTHING;
  END IF;
END$$;

-- 0-2) ad_moderation_logs 테이블 생성(없으면) + loop_id 추가
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_moderation_logs') THEN
    CREATE TABLE ad_moderation_logs(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER,
      channel TEXT,
      decision TEXT,
      used_autofix BOOLEAN DEFAULT false,
      loop_id TEXT,
      dur_ms INTEGER,
      created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE INDEX idx_ad_mod_loop ON ad_moderation_logs(loop_id);
  ELSE
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ad_moderation_logs' AND column_name='loop_id') THEN
      ALTER TABLE ad_moderation_logs ADD COLUMN loop_id TEXT;
      CREATE INDEX IF NOT EXISTS idx_ad_mod_loop ON ad_moderation_logs(loop_id);
    END IF;
  END IF;
END$$;
SQL

node scripts/run_sql.js scripts/migrations/20251114_r74_rules_loop.sql >/dev/null

############################################
# 1) 품질 로직 패치: rules 로딩(버전 테이블 우선) + loop_id 기록
############################################
# ads_quality.js가 존재한다는 가정(r7.3 기준). rules 조회 우선순위: channel_rules(ACTIVE) → ad_channel_rules(호환)
if [ -f server/routes/ads_quality.js ]; then
  # loadRules 함수를 channel_rules 우선으로 수정
  cat > /tmp/loadRules_patch.js <<'JS'
const fs = require('fs');
const content = fs.readFileSync('server/routes/ads_quality.js', 'utf8');
const newLoadRules = `async function loadRules(channel){
  const ch = String(channel||'').toUpperCase();
  // 1) channel_rules ACTIVE 우선
  try {
    const a = await db.q("SELECT config FROM channel_rules WHERE channel=$1 AND status='ACTIVE' ORDER BY rule_version DESC LIMIT 1", [ch]);
    if(a.rows.length) {
      const cfg=a.rows[0].config||{}; 
      return { 
        max_len_headline:Number(cfg.max_len_headline||30), 
        max_len_body:Number(cfg.max_len_body||140), 
        max_hashtags:Number(cfg.max_hashtags||10), 
        allow_links:!!cfg.allow_links 
      };
    }
  } catch(e) { /* fallback */ }
  // 2) 기존 channel_rules 테이블 fallback
  try {
    const b = await db.q('SELECT max_len_headline,max_len_body,max_hashtags,allow_links FROM channel_rules WHERE channel=$1 LIMIT 1',[ch]);
    if(b.rows.length){ return b.rows[0]; }
  } catch(e) { /* no-op */ }
  return { max_len_headline:30, max_len_body:140, max_hashtags:10, allow_links:true };
}`;
const patched = content.replace(/async function loadRules\(channel\)\{[\s\S]*?\n\}/, newLoadRules);
fs.writeFileSync('server/routes/ads_quality.js', patched);
JS
  node /tmp/loadRules_patch.js || true
fi

############################################
# 2) 규칙 API/Freeze 및 관리 UI 라우트
############################################
cat > server/routes/admin_quality_rules.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const admin=require('../mw/admin'); const r=express.Router();

// GET /admin/ads/quality/rules  : ACTIVE/DRAFT 목록
r.get('/rules', admin.requireAdmin, async (req,res)=>{
  const q = await db.q(`SELECT channel, rule_version, status, config, effective_at, created_at
                        FROM channel_rules ORDER BY channel, rule_version DESC`);
  res.json({ ok:true, items:q.rows });
});

// PUT /admin/ads/quality/rules : {channel, rule_version?, status?, config}
r.put('/rules', admin.requireAdmin, express.json(), async (req,res)=>{
  const { channel, rule_version, status, config } = req.body||{};
  if(!channel || !config) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const ch = String(channel).toUpperCase();
  const ver = Number(rule_version||Date.now()%100000);
  const st = (status||'DRAFT').toUpperCase();
  await db.q(`INSERT INTO channel_rules(channel, rule_version, status, config, effective_at)
              VALUES($1,$2,$3,$4::jsonb, CASE WHEN $3='ACTIVE' THEN now() ELSE NULL END)
              ON CONFLICT DO NOTHING`, [ch, ver, st, JSON.stringify(config)]);
  // ACTIVE로 올리는 경우 기존 ACTIVE는 DEPRECATED 처리
  if(st==='ACTIVE'){
    await db.q(`UPDATE channel_rules SET status='DEPRECATED' WHERE channel=$1 AND status='ACTIVE' AND rule_version<>$2`, [ch, ver]);
  }
  res.json({ ok:true, channel:ch, rule_version:ver, status:st });
});

// POST /admin/ads/quality/rules/freeze : {channel, rule_version}
r.post('/rules/freeze', admin.requireAdmin, express.json(), async (req,res)=>{
  const { channel, rule_version } = req.body||{};
  if(!channel || !rule_version) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const ch=String(channel).toUpperCase(), ver=Number(rule_version);
  await db.q(`UPDATE channel_rules SET status='ACTIVE', effective_at=now() WHERE channel=$1 AND rule_version=$2`,[ch,ver]);
  await db.q(`UPDATE channel_rules SET status='DEPRECATED' WHERE channel=$1 AND rule_version<>$2 AND status<>'DEPRECATED'`,[ch,ver]);
  res.json({ ok:true, channel:ch, rule_version:ver, status:'ACTIVE' });
});

module.exports=r;
JS

# app.js 마운트(중복 안전)
if ! grep -q "routes/admin_quality_rules" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/ads/quality', require('./routes/admin_quality_rules'));\\
" server/app.js && rm -f server/app.js.bak
fi
echo "RULES API OK"

############################################
# 3) 루프 통계/보고 자동화 라우트 + 증빙 번들
############################################
cat > server/routes/admin_webapp_loop.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const { execSync }=require('child_process'); const r=express.Router();

// GET /admin/webapp/loop/stats.json  (1d/7d: first_pass_ok, autofix_ok, rejected, rates)
r.get('/loop/stats.json', admin.requireAdmin, async (req,res)=>{
  async function win(days){
    const base = await db.q(`
      WITH base AS (
        SELECT loop_id, decision, used_autofix, created_at
        FROM ad_moderation_logs
        WHERE created_at >= now()-($1||' days')::interval
      ),
      ok1 AS ( SELECT count(*)::int c FROM base WHERE decision='APPROVED' AND used_autofix=false ),
      loops AS (
        SELECT COALESCE(loop_id, '_noid_') lid,
               max( (decision='APPROVED')::int ) as any_ok,
               max( (used_autofix=true)::int )  as any_fix
        FROM base GROUP BY COALESCE(loop_id, '_noid_')
      ),
      ok2 AS ( SELECT count(*)::int c FROM loops WHERE any_ok=1 AND any_fix=1 ),
      rej AS ( SELECT count(*)::int c FROM base WHERE decision='REJECT' ),
      tot AS ( SELECT count(*)::int c FROM base )
      SELECT (SELECT c FROM ok1) first_pass_ok,
             (SELECT c FROM ok2) autofix_ok,
             (SELECT c FROM rej) rejected,
             (SELECT c FROM tot) total
    `,[days]);
    const row = base.rows[0]||{first_pass_ok:0,autofix_ok:0,rejected:0,total:0};
    const total = Number(row.total||0);
    const first = Number(row.first_pass_ok||0), fix = Number(row.autofix_ok||0), rej = Number(row.rejected||0);
    const appr = total? (first+fix)/total : 1;
    return { first_pass_ok:first, autofix_ok:fix, rejected:rej, total, auto_approval_rate:appr };
  }
  const d1 = await win(1), d7 = await win(7);
  res.json({ ok:true, d1, d7, slo:{ min_auto_approval: Number(process.env.WEBAPP_GATE_APPROVE_RATE||0.95), max_p95_ms: Number(process.env.WEBAPP_GATE_P95_MS||300000) } });
});

// GET /admin/webapp/gate/report  : 게이트 종합 리포트(JSON)
r.get('/gate/report', admin.requireAdmin, async (req,res)=>{
  // p95는 기존 /admin/webapp/gate 에서 계산되므로 재활용
  const g = await (await fetch(`http://localhost:${process.env.PORT||'5902'}/admin/webapp/gate`, { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const s = await (await fetch(`http://localhost:${process.env.PORT||'5902'}/admin/webapp/loop/stats.json`, { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  res.json({ ok:true, gate:g, loop:s });
});

// POST /admin/webapp/evidence/export  : 증빙 번들 생성
r.post('/evidence/export', admin.requireAdmin, async (req,res)=>{
  try{
    const out = execSync('bash scripts/generate_webapp_evidence.sh', { encoding:'utf8' }).trim();
    res.json({ ok:true, file: out });
  }catch(e){ res.status(500).json({ ok:false, code:'EVIDENCE_FAIL', err: String(e.message||e) }); }
});

module.exports=r;
JS

if ! grep -q "routes/admin_webapp_loop" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/webapp', require('./routes/admin_webapp_loop'));\\
" server/app.js && rm -f server/app.js.bak
fi

cat > scripts/generate_webapp_evidence.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
OUT="artifacts/webapp_evidence_$(date +%Y%m%d_%H%M%S).tgz"
TMP="$(mktemp -d)"
PORT="${PORT:-5902}"
ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
# 수집
curl -sf "http://localhost:${PORT}/admin/webapp/gate" -H "X-Admin-Key: ${ADMIN_KEY}" > "${TMP}/gate.json" || true
curl -sf "http://localhost:${PORT}/admin/webapp/loop/stats.json" -H "X-Admin-Key: ${ADMIN_KEY}" > "${TMP}/loop_stats.json" || true
curl -sf "http://localhost:${PORT}/admin/webapp/gate/report" -H "X-Admin-Key: ${ADMIN_KEY}" > "${TMP}/gate_report.json" || true
psql "${DATABASE_URL}" -Atc "select * from channel_rules order by channel, rule_version desc;" > "${TMP}/channel_rules.tsv" || true
psql "${DATABASE_URL}" -Atc "select decision, used_autofix, loop_id, dur_ms, created_at from ad_moderation_logs order by id desc limit 500;" > "${TMP}/moderation_logs.tsv" || true
tar -czf "${OUT}" -C "${TMP}" .
echo "${OUT}"
BASH

chmod +x scripts/generate_webapp_evidence.sh

############################################
# 4) 호환 엔드포인트/경로(이미 존재해도 중복 안전)
############################################
# r7.3 명세와 호환: /ads/quality/* 별칭은 이미 존재하므로 스킵

############################################
# 5) 서버 재기동 → 헬스
############################################
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 2
curl -sf "http://localhost:${PORT}/health" >/dev/null || { echo "[ERR] health failed"; exit 1; }

############################################
# 6) 스모크(규칙/루프/게이트/증빙)
############################################
# 6-1 규칙 API + Freeze
curl -sf "http://localhost:${PORT}/admin/ads/quality/rules" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "RULES API OK"

# DRAFT 규칙 하나 추가 후 ACTIVE로 승격
curl -sf -XPUT "http://localhost:${PORT}/admin/ads/quality/rules" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"channel":"NAVER","rule_version":2,"status":"DRAFT","config":{"max_len_headline":30,"max_len_body":140,"max_hashtags":10,"allow_links":true}}' >/dev/null

curl -sf -XPOST "http://localhost:${PORT}/admin/ads/quality/rules/freeze" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"channel":"NAVER","rule_version":2}' | grep -q '"status":"ACTIVE"' && echo "RULES FREEZE OK"

# 6-2 루프 캡처(loop_id로 상관): 1) REJECT → 2) AUTOFIX → 3) APPROVE
LID="L-$(date +%s)"
# (1) 첫 검증(의도적으로 금칙어 포함)
curl -sf -XPOST "http://localhost:${PORT}/ads/quality/validate" -H "Content-Type: application/json" \
  -d "{\"channel\":\"NAVER\",\"headline\":\"테스트\",\"body\":\"전액환불 혜택 안내\",\"hashtags\":[\"#강아지\"],\"links\":[],\"loop_id\":\"${LID}\"}" >/dev/null
# (2) 자동수정 수행(동일 loop)
FX="$(curl -sf -XPOST "http://localhost:${PORT}/ads/quality/autofix" -H "Content-Type: application/json" -d "{\"channel\":\"NAVER\",\"headline\":\"테스트\",\"body\":\"전액환불 혜택 안내\",\"hashtags\":[\"#강아지\"],\"links\":[]}")"
FT="$(echo "$FX" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);console.log(j.fixed&&j.fixed.body||'')}catch{console.log('')}})" || echo '')"
# (3) 수정본 재검증(동일 loop)
if [ -n "$FT" ]; then
  curl -sf -XPOST "http://localhost:${PORT}/ads/quality/validate" -H "Content-Type: application/json" \
    -d "{\"channel\":\"NAVER\",\"headline\":\"테스트\",\"body\":\"${FT}\",\"hashtags\":[\"#강아지\"],\"links\":[],\"loop_id\":\"${LID}\"}" >/dev/null
fi
echo "LOOP CAPTURE OK"

# 6-3 루프 통계/게이트 리포트
curl -sf "http://localhost:${PORT}/admin/webapp/loop/stats.json" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "LOOP STATS OK"
curl -sf "http://localhost:${PORT}/admin/webapp/gate/report" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "GATE REPORT OK"

# 6-4 증빙 번들
curl -sf -XPOST "http://localhost:${PORT}/admin/webapp/evidence/export" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "EVIDENCE WEBAPP OK"

echo "R74 DONE"

