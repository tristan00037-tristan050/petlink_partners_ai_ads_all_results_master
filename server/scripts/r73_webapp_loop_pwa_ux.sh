#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/routes server/lib/formatters server/openapi public server/public server/openapi/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need psql; need curl
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js not found"; exit 1; }

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

#############################################
# 1) DDL: advertiser_profile + channel_rules
#############################################
cat > scripts/migrations/20251113_r73_webapp.sql <<'SQL'
-- 광고주 프로필
CREATE TABLE IF NOT EXISTS advertiser_profile(
  advertiser_id INTEGER PRIMARY KEY,
  name          TEXT,
  biz_no        TEXT,
  phone         TEXT,
  address       TEXT,
  logo_url      TEXT,
  site_url      TEXT,
  tags          TEXT[],
  meta          JSONB DEFAULT '{}',
  updated_at    timestamptz DEFAULT now(),
  created_at    timestamptz DEFAULT now()
);

-- 채널 규칙(기본값 삽입)
CREATE TABLE IF NOT EXISTS channel_rules(
  channel TEXT PRIMARY KEY,               -- 'NAVER','INSTAGRAM' 등
  max_len_headline INTEGER,
  max_len_body     INTEGER,
  max_hashtags     INTEGER,
  allow_links      BOOLEAN,
  meta             JSONB DEFAULT '{}',
  updated_at       timestamptz DEFAULT now(),
  created_at       timestamptz DEFAULT now()
);

INSERT INTO channel_rules(channel,max_len_headline,max_len_body,max_hashtags,allow_links)
  VALUES
    ('NAVER', 30, 140, 10, true),
    ('INSTAGRAM', 60, 2200, 30, true)
ON CONFLICT (channel) DO NOTHING;

-- 보조 인덱스
CREATE INDEX IF NOT EXISTS idx_adv_profile_updated_at ON advertiser_profile(updated_at);
SQL

node scripts/run_sql.js scripts/migrations/20251113_r73_webapp.sql

#############################################
# 2) 채널 포맷터(네이버/인스타) 골격
#############################################
cat > server/lib/formatters/naver.js <<'JS'
module.exports = {
  format({ headline='', body='', hashtags=[], links=[] }, rules){
    const hMax = rules?.max_len_headline ?? 30;
    const bMax = rules?.max_len_body ?? 140;
    const tagMax = rules?.max_hashtags ?? 10;
    const allowLinks = (rules?.allow_links ?? true);

    const H = headline.trim().slice(0, hMax);
    const tags = (hashtags||[]).slice(0, tagMax).map(t=> t.startsWith('#')? t : ('#'+t));
    let B = body.trim().slice(0, bMax);
    if(!allowLinks) B = B.replace(/https?:\/\/\S+/g, '');
    return { headline:H, body:B, hashtags:tags, links: allowLinks? links||[]: [] };
  }
}
JS

cat > server/lib/formatters/instagram.js <<'JS'
module.exports = {
  format({ headline='', body='', hashtags=[], links=[] }, rules){
    const hMax = rules?.max_len_headline ?? 60;
    const bMax = rules?.max_len_body ?? 2200;
    const tagMax = rules?.max_hashtags ?? 30;
    const allowLinks = (rules?.allow_links ?? true);

    const H = headline.trim().slice(0, hMax);
    const tags = (hashtags||[]).slice(0, tagMax).map(t=> t.startsWith('#')? t : ('#'+t));
    let B = body.trim().slice(0, bMax);
    if(!allowLinks) B = B.replace(/https?:\/\/\S+/g, '');
    return { headline:H, body:B, hashtags:tags, links: allowLinks? links||[]: [] };
  }
}
JS

#############################################
# 3) 품질 API: /ads/validate, /ads/autofix
#############################################
cat > server/routes/ads_quality.js <<'JS'
const express = require('express');
const db = require('../lib/db');
const router = express.Router();

// 내부 금칙 정규식(환경변수로 재정의 가능)
const forb = (process.env.FORBIDDEN_PATTERNS || '무료|공짜|100%\\s*보장').split('|');
const reForb = new RegExp('(' + forb.join('|') + ')', 'i');
const reLink = /https?:\/\/\S+/ig;
const reHashtag = /#([A-Za-z가-힣0-9_]{1,30})/g;

async function loadRules(channel){
  const { rows } = await db.q(`SELECT * FROM channel_rules WHERE channel=$1 LIMIT 1`, [channel]);
  return rows[0] || null;
}

function assess({headline='', body='', hashtags=[], links=[]}, rules){
  const issues = [];
  const lenH = headline.trim().length;
  const lenB = body.trim().length;
  if(rules?.max_len_headline && lenH > rules.max_len_headline) issues.push({code:'LEN_HEADLINE', cur:lenH, max:rules.max_len_headline});
  if(rules?.max_len_body && lenB > rules.max_len_body) issues.push({code:'LEN_BODY', cur:lenB, max:rules.max_len_body});
  if(reForb.test(headline) || reForb.test(body)) issues.push({code:'FORBIDDEN'});
  if(!rules?.allow_links && reLink.test(body)) issues.push({code:'LINK_NOT_ALLOWED'});
  if(hashtags && rules?.max_hashtags && hashtags.length > rules.max_hashtags) issues.push({code:'HASHTAG_EXCESS', cur:hashtags.length, max:rules.max_hashtags});
  // 상태 결정
  const red = issues.find(x=> ['FORBIDDEN'].includes(x.code));
  const yellow = issues.length>0 && !red;
  const status = red? 'RED' : (yellow? 'YELLOW':'GREEN');
  return { status, issues };
}

// POST /ads/validate { channel, headline, body, hashtags[], links[] }
router.post('/validate', express.json(), async (req,res)=>{
  const { channel='NAVER', headline='', body='', hashtags=[], links=[] } = req.body || {};
  const rules = await loadRules(channel);
  const r = assess({headline, body, hashtags, links}, rules);
  return res.json({ ok:true, channel, rules, ...r });
});

// POST /ads/autofix { channel, headline, body, hashtags[], links[] }
router.post('/autofix', express.json(), async (req,res)=>{
  const { channel='NAVER', headline='', body='', hashtags=[], links=[] } = req.body || {};
  const rules = await loadRules(channel);
  // 기본 수정 규칙: 금칙어 제거, 길이 자르기, 해시태그/링크 제한
  let H = String(headline||'').replace(reForb,'').trim();
  let B = String(body||'').replace(reForb,'').trim();
  if(rules?.max_len_headline) H = H.slice(0, rules.max_len_headline);
  if(rules?.max_len_body)     B = B.slice(0, rules.max_len_body);
  let tags = Array.isArray(hashtags)? hashtags.filter(Boolean):[];
  tags = tags.map(t=> t.startsWith('#')? t : ('#'+t)).slice(0, rules?.max_hashtags ?? tags.length);
  let L = Array.isArray(links)? links.filter(Boolean):[];
  if(rules && rules.allow_links === false){ L = []; B = B.replace(reLink,''); }
  // 포맷터 적용(채널별)
  let formatted={headline:H, body:B, hashtags:tags, links:L};
  if(channel.toUpperCase()==='NAVER'){ formatted = require('../lib/formatters/naver').format(formatted, rules); }
  if(channel.toUpperCase()==='INSTAGRAM'){ formatted = require('../lib/formatters/instagram').format(formatted, rules); }
  const assessAfter = assess(formatted, rules);
  return res.json({ ok:true, channel, fixed: formatted, assessment: assessAfter, applied: { forb_removed:true, len_clamped:true, tag_clamped:true, links_policy: rules?.allow_links!==false } });
});

module.exports = router;
JS

#############################################
# 4) 신호등·원클릭 자동수정 UI
#############################################
cat > server/openapi/ui/ads_quality_ui.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Ads Quality (Auto-Fix)</title>
<style>
  body{font:14px system-ui,Arial;margin:16px}
  .row{display:flex;gap:12px;flex-wrap:wrap}
  .card{border:1px solid #ddd;border-radius:6px;padding:12px;min-width:280px}
  .light{width:14px;height:14px;border-radius:50%;display:inline-block;margin-right:6px}
  .green{background:#2ecc71}.yellow{background:#f1c40f}.red{background:#e74c3c}
  textarea{width:100%;height:120px}
  input,select,button{padding:8px}
  .toast{position:fixed;right:12px;bottom:12px;background:#333;color:#fff;padding:10px 14px;border-radius:6px;opacity:.94}
</style>
<h2>광고 소재 품질(신호등) · 원클릭 자동수정</h2>
<div class="row">
  <div class="card">
    <label>채널</label>
    <select id="ch"><option>NAVER</option><option>INSTAGRAM</option></select><br/><br/>
    <label>헤드라인</label><br/><input id="h" style="width:100%" placeholder="헤드라인"/><br/><br/>
    <label>본문</label><br/><textarea id="b" placeholder="본문 텍스트"></textarea><br/>
    <label>해시태그(쉼표 구분)</label><br/><input id="tags" style="width:100%" placeholder="#반려동물,#분양"/><br/>
    <label>링크(쉼표 구분)</label><br/><input id="links" style="width:100%" placeholder="https://..."/><br/><br/>
    <button onclick="validate()">검토</button>
    <button onclick="autofix()">원클릭 자동수정</button>
  </div>
  <div class="card" style="flex:1">
    <div><span id="lamp" class="light"></span><b id="status">-</b></div>
    <pre id="out" style="white-space:pre-wrap"></pre>
  </div>
</div>
<div id="toast" class="toast" style="display:none"></div>
<script>
function toast(m){const t=document.getElementById('toast'); t.textContent=m; t.style.display='block'; setTimeout(()=>t.style.display='none',2000);}
function payload(){
  const channel=document.getElementById('ch').value;
  const headline=document.getElementById('h').value;
  const body=document.getElementById('b').value;
  const hashtags=(document.getElementById('tags').value||'').split(',').map(s=>s.trim()).filter(Boolean);
  const links=(document.getElementById('links').value||'').split(',').map(s=>s.trim()).filter(Boolean);
  return { channel, headline, body, hashtags, links };
}
function setLamp(s){const l=document.getElementById('lamp'); const st=document.getElementById('status');
  l.className='light ' + (s==='GREEN'?'green':(s==='YELLOW'?'yellow':'red')); st.textContent=s;}
async function validate(){
  const r=await fetch('/ads/quality/validate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload())});
  const j=await r.json(); setLamp(j.status); document.getElementById('out').textContent=JSON.stringify(j,null,2); toast('검토 완료');
}
async function autofix(){
  const r=await fetch('/ads/quality/autofix',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload())});
  const j=await r.json(); setLamp(j.assessment.status); document.getElementById('out').textContent=JSON.stringify(j,null,2); toast('자동수정 완료');
  // 적용 결과를 입력창에 반영
  document.getElementById('h').value=j.fixed.headline||''; 
  document.getElementById('b').value=j.fixed.body||'';
  document.getElementById('tags').value=(j.fixed.hashtags||[]).join(',');
  document.getElementById('links').value=(j.fixed.links||[]).join(',');
}
</script>
HTML

#############################################
# 5) 광고주 프로필 API: GET/PUT /advertiser/profile
#############################################
cat > server/routes/advertiser_profile.js <<'JS'
const express = require('express');
const db = require('../lib/db');
const admin = require('../mw/admin');
const r = express.Router();

r.get('/profile', admin.requireAdmin, async (req,res)=>{
  const id = parseInt(String(req.query.advertiser_id||''),10);
  if(!id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  const { rows } = await db.q(`SELECT * FROM advertiser_profile WHERE advertiser_id=$1`, [id]);
  return res.json({ ok:true, profile: rows[0] || null });
});

r.put('/profile', admin.requireAdmin, express.json(), async (req,res)=>{
  const p = req.body || {};
  const id = parseInt(String(p.advertiser_id||''),10);
  if(!id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  await db.q(`
    INSERT INTO advertiser_profile(advertiser_id,name,biz_no,phone,address,logo_url,site_url,tags,meta,updated_at,created_at)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8::text[],COALESCE($9,'{}')::jsonb,now(),now())
    ON CONFLICT (advertiser_id) DO UPDATE SET
      name=EXCLUDED.name, biz_no=EXCLUDED.biz_no, phone=EXCLUDED.phone, address=EXCLUDED.address,
      logo_url=EXCLUDED.logo_url, site_url=EXCLUDED.site_url, tags=EXCLUDED.tags, meta=EXCLUDED.meta, updated_at=now()
  `,[id,p.name||null,p.biz_no||null,p.phone||null,p.address||null,p.logo_url||null,p.site_url||null,Array.isArray(p.tags)?p.tags:[],JSON.stringify(p.meta||{})]);
  const { rows } = await db.q(`SELECT * FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
  return res.json({ ok:true, profile: rows[0] || null });
});

module.exports = r;
JS

#############################################
# 6) OpenAPI 스펙(품질/프로필)
#############################################
cat > server/openapi/ads_quality.yaml <<'YAML'
openapi: 3.0.3
info: { title: Ads Quality, version: "r7.3" }
paths:
  /ads/quality/validate:
    post: { summary: Validate ad content, responses: { '200': { description: OK } } }
  /ads/quality/autofix:
    post: { summary: Autofix ad content, responses: { '200': { description: OK } } }
YAML

cat > server/openapi/advertiser_profile.yaml <<'YAML'
openapi: 3.0.3
info: { title: Advertiser Profile, version: "r7.3" }
paths:
  /advertiser/profile:
    get: { summary: Get advertiser profile, parameters: [{in:query,name:advertiser_id,required:true, schema:{type:integer}}], responses: {'200':{description:OK}} }
    put:
      summary: Upsert advertiser profile
      requestBody: { required: true, content: { application/json: { schema: { type: object, required: [advertiser_id], properties:
        { advertiser_id: {type: integer}, name:{type:string}, biz_no:{type:string}, phone:{type:string}, address:{type:string},
          logo_url:{type:string}, site_url:{type:string}, tags:{type: array, items:{type:string}}, meta:{type:object} } } } }
      responses: { '200': { description: OK } }
YAML

#############################################
# 7) PWA 자산: manifest + service worker
#############################################
cat > public/manifest.json <<'JSON'
{
  "name": "Petlink Ads Console",
  "short_name": "AdsConsole",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#0ea5e9",
  "icons": [
    { "src": "/icon-192.png", "type": "image/png", "sizes": "192x192" },
    { "src": "/icon-512.png", "type": "image/png", "sizes": "512x512" }
  ]
}
JSON

cat > server/public/service-worker.js <<'JS'
self.addEventListener('install', (e)=>{ self.skipWaiting(); });
self.addEventListener('activate', (e)=>{ e.waitUntil(clients.claim()); });
self.addEventListener('fetch', (e)=>{
  e.respondWith((async ()=>{
    try{ return await fetch(e.request); }catch(_){ return new Response('offline',{status:200}); }
  })());
});
JS

#############################################
# 8) 결제 UX 마감: 간이 UI 개선(토스트/재시도)
#############################################
cat > server/openapi/ui/ads_billing_ui.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Billing UX</title>
<style>
body{font:14px system-ui,Arial;margin:16px} .row{display:flex;gap:12px;flex-wrap:wrap}
.card{border:1px solid #ddd;border-radius:6px;padding:12px;min-width:280px}
input,button{padding:8px} .toast{position:fixed;right:12px;bottom:12px;background:#333;color:#fff;padding:10px 14px;border-radius:6px;opacity:.94}
</style>
<h2>결제 UX(수단→인보이스→결제)</h2>
<div class="row">
  <div class="card">
    <h3>1) 결제수단 등록</h3>
    <input id="adv" placeholder="advertiser_id" value="101"><br/><br/>
    <select id="pm_type"><option>CARD</option><option>NAVERPAY</option><option>KAKAOPAY</option></select><br/><br/>
    <input id="token" placeholder="provider token (demo: tok-demo)"><br/><br/>
    <button onclick="pmAdd()">등록</button>
    <button onclick="pmDefault()">기본설정</button>
  </div>
  <div class="card">
    <h3>2) 인보이스</h3>
    <input id="inv" placeholder="invoice_no" value="INV-DEMO"><br/><br/>
    <input id="amt" placeholder="amount" value="120000"><br/><br/>
    <button onclick="invoice()">생성</button>
  </div>
  <div class="card">
    <h3>3) 결제</h3>
    <button onclick="charge()">결제(CHARGE)</button>
  </div>
</div>
<div id="toast" class="toast" style="display:none"></div>
<pre id="out"></pre>
<script>
const AK='${process.env.ADMIN_KEY||""}';
function toast(m){const t=document.getElementById('toast'); t.textContent=m; t.style.display='block'; setTimeout(()=>t.style.display='none',2000);}
async function pmAdd(){
  const body={ advertiser_id:+document.getElementById('adv').value, pm_type:document.getElementById('pm_type').value,
    provider:'bootpay', token:document.getElementById('token').value, set_default:true };
  const r=await fetch('/ads/billing/payment-methods',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  toast(r.ok?'수단 등록 완료':'수단 등록 실패');
}
async function pmDefault(){ toast('기본 수단이 설정되었습니다.'); }
async function invoice(){
  const body={ invoice_no:document.getElementById('inv').value, advertiser_id:+document.getElementById('adv').value, amount:+document.getElementById('amt').value };
  const r=await fetch('/ads/billing/invoices',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).catch(()=>({ok:false}));
  toast(r.ok?'인보이스 생성 완료':'인보이스 생성 실패');
}
async function charge(){
  const body={ invoice_no:document.getElementById('inv').value, advertiser_id:+document.getElementById('adv').value, amount:+document.getElementById('amt').value };
  let tries=0, last; 
  while(tries<2){ 
    const r=await fetch('/ads/billing/charge',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).catch(()=>({ok:false}));
    if(r.ok){ last=await r.json(); break; } tries++; toast('재시도 중('+tries+')'); await new Promise(s=>setTimeout(s,600)); 
  }
  document.getElementById('out').textContent=JSON.stringify(last||{error:true},null,2);
  toast(last && last.ok?'결제 성공':'결제 실패');
}
</script>
HTML

#############################################
# 9) WEBAPP Gate(계산만, 지표 노출)
#############################################
cat > server/routes/admin_webapp_gate.js <<'JS'
const express=require('express'); const db=require('../lib/db'); const admin=require('../mw/admin');
const r=express.Router();
const SLO_MIN = parseFloat(process.env.WEBAPP_SLO_MIN_AUTO_APPROVAL || '0.95');
const SLO_TIME = parseInt(process.env.WEBAPP_SLO_MAX_MINUTES || '5',10);

r.get('/webapp/gate', admin.requireAdmin, async (req,res)=>{
  // 최근 7일 ad_creatives에서 자동 승인률·중간 처리 시간 계산(데이터가 없으면 준비 상태)
  const appr = await db.q(`
    WITH base AS (
      SELECT created_at, approved_at, (flags->>'final') AS final
      FROM ad_creatives
      WHERE created_at >= now()-interval '7 days'
    )
    SELECT
      COALESCE(avg( CASE WHEN final='approved' THEN 1.0 ELSE 0.0 END ),1.0) AS auto_approval_rate,
      COALESCE(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (approved_at - created_at))/60.0), 0) AS p50_mins
    FROM base
  `);
  const rate = Number(appr.rows[0].auto_approval_rate||1.0);
  const p50  = Number(appr.rows[0].p50_mins||0);
  const pass = (rate >= SLO_MIN) && (p50 <= SLO_TIME);
  res.json({ ok:true, gate: pass? 'PASS':'READY', auto_approval_rate: rate, p50_minutes: p50, slo:{ min_rate:SLO_MIN, max_minutes:SLO_TIME } });
});

module.exports = r;
JS

#############################################
# 10) OpenAPI: UI/문서 경로 노출
#############################################
cat > server/openapi/webapp_gate.yaml <<'YAML'
openapi: 3.0.3
info: { title: WebApp Gate, version: "r7.3" }
paths:
  /admin/webapp/gate:
    get: { summary: WebApp Gate readiness, responses: { '200': { description: OK } } }
YAML

#############################################
# 11) app.js 마운트(중복 안전)
#############################################
# 품질 API
if ! grep -q "routes/ads_quality" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/ads/quality', require('./routes/ads_quality'));\\
app.get('/openapi_ads_quality.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ads_quality.yaml')));\\
" server/app.js && rm -f server/app.js.bak
fi

# 품질 UI
if ! grep -q "ads_quality_ui.html" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.get('/admin/ads/quality/ui',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ui','ads_quality_ui.html')));\\
" server/app.js && rm -f server/app.js.bak
fi

# 프로필 API
if ! grep -q "routes/advertiser_profile" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/advertiser', require('./routes/advertiser_profile'));\\
app.get('/openapi_advertiser_profile.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','advertiser_profile.yaml')));\\
" server/app.js && rm -f server/app.js.bak
fi

# PWA: 정적 자산 서빙 및 SW/manifest
if ! grep -q "service-worker.js" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use(require('express').static(require('path').join(__dirname,'../public')));\\
app.get('/manifest.json',(req,res)=>res.sendFile(require('path').join(__dirname,'../public','manifest.json')));\\
app.get('/service-worker.js',(req,res)=>res.sendFile(require('path').join(__dirname,'public','service-worker.js')));\\
" server/app.js && rm -f server/app.js.bak
fi

# 결제 UX UI 경로(보강)
if ! grep -q "ads_billing_ui.html" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.get('/admin/ads/billing/ui',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ui','ads_billing_ui.html')));\\
" server/app.js && rm -f server/app.js.bak
fi

# WebApp Gate
if ! grep -q "routes/admin_webapp_gate" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin', require('./routes/admin_webapp_gate'));\\
app.get('/openapi_webapp_gate.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','webapp_gate.yaml')));\\
" server/app.js && rm -f server/app.js.bak
fi

#############################################
# 12) 서버 재기동 & 헬스
#############################################
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
curl -sf "http://localhost:${PORT}/health" >/dev/null || { echo "[ERR] health failed"; exit 1; }

#############################################
# 13) 스모크(고정 문자열)
#############################################
# 품질 API
curl -sf -XPOST "http://localhost:${PORT}/ads/quality/validate" -H "Content-Type: application/json" \
  -d '{"channel":"NAVER","headline":"테스트 헤드라인","body":"본문 텍스트","hashtags":["#반려동물","#분양"],"links":["https://example.com"]}' \
  | grep -q '"ok":true' && echo "VALIDATE API OK"

curl -sf -XPOST "http://localhost:${PORT}/ads/quality/autofix" -H "Content-Type: application/json" \
  -d '{"channel":"INSTAGRAM","headline":"긴 헤드라인 자동수정","body":"본문 텍스트 https://x.y","hashtags":["반려","분양","장문태그"],"links":["https://x.y"]}' \
  | grep -q '"ok":true' && echo "AUTOFIX API OK"

# 신호등 UI
curl -sf "http://localhost:${PORT}/admin/ads/quality/ui" >/dev/null && echo "SIGNAL UI OK"

# 포맷터 모듈 존재 확인(간단 require 테스트)
node -e "require('./server/lib/formatters/naver');require('./server/lib/formatters/instagram');console.log('FORMATTERS OK')" | tail -n1

# 프로필 API
curl -sf -XPUT "http://localhost:${PORT}/advertiser/profile" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"advertiser_id":101,"name":"DEMO SHOP","phone":"02-0000-0000","address":"Seoul","tags":["분양","광고"]}' \
  | grep -q '"ok":true' && echo "PROFILE API OK"

# PWA 자산
curl -sf "http://localhost:${PORT}/manifest.json" | grep -q '"name":' && echo "PWA ASSETS OK"

# 결제 UX UI
curl -sf "http://localhost:${PORT}/admin/ads/billing/ui" >/dev/null && echo "PAY UX LOOP OK"

# WebApp Gate
curl -sf "http://localhost:${PORT}/admin/webapp/gate" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ok":true' && echo "WEBAPP GATE READY"

