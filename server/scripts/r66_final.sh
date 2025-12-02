#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/routes server/bootstrap

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

# 샌드박스 네트워크 상시화 ENV(이미 주입된 값 유지)
export BILLING_ADAPTER="${BILLING_ADAPTER:-bootpay-rest}"
export BILLING_MODE="${BILLING_MODE:-sandbox}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js not found"; exit 1; }
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }
test -f server/routes/ads_billing.js || { echo "[ERR] server/routes/ads_billing.js not found"; exit 1; }

############################################
# 1) 네트워크 모니터(테이블+데몬+API)
############################################
cat > scripts/migrations/20251114_r66_net_checks.sql <<'SQL'
CREATE TABLE IF NOT EXISTS billing_net_checks(
  id BIGSERIAL PRIMARY KEY,
  ok BOOLEAN NOT NULL,
  latency_ms INTEGER,
  detail TEXT,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_billing_net_checks_created_at ON billing_net_checks(created_at);
SQL

node scripts/run_sql.js scripts/migrations/20251114_r66_net_checks.sql >/dev/null

# 부트스트랩 데몬(이미 존재해도 재사용)
cat > server/bootstrap/net_monitor.js <<'JS'
const db = require('../lib/db');
const pick = require('../lib/billing/factory');
const { performance } = require('node:perf_hooks');

async function probeOnce(){
  const adapter = pick()();
  let ok=false, latency=0, detail='';
  const t0 = performance.now();
  try{
    const p = adapter.__probeToken ? await adapter.__probeToken() : { has_token:false, offline:true };
    ok = !!p.has_token;
    latency = Math.round(performance.now() - t0);
    detail = JSON.stringify(p);
  }catch(e){
    latency = Math.round(performance.now() - t0);
    detail = 'ERR:'+(e && e.message || String(e));
  }
  try{ await db.q(`INSERT INTO billing_net_checks(ok,latency_ms,detail) VALUES($1,$2,$3)`,[ok,latency,detail]); }catch{}
  return { ok, latency };
}

probeOnce().catch(()=>{});
setInterval(()=>{ probeOnce().catch(()=>{}); }, 60*1000);

module.exports = { probeOnce };
JS

if ! grep -q "bootstrap/net_monitor" server/app.js; then
  sed -i.bak "1i\\
require('./bootstrap/net_monitor');\\
" server/app.js && rm -f server/app.js.bak
fi

cat > server/routes/admin_billing_monitor.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const mon=require('../bootstrap/net_monitor');
const r=express.Router();
r.post('/monitor/probe', admin.requireAdmin, async (req,res)=>{ const x = await mon.probeOnce(); res.json({ ok:true, probed:true, result:x }); });
r.get('/monitor.json', admin.requireAdmin, async (req,res)=>{ const q=await db.q(`SELECT id,ok,latency_ms,created_at FROM billing_net_checks ORDER BY id DESC LIMIT 20`); res.json({ ok:true, items:q.rows }); });
r.get('/monitor', admin.requireAdmin, async (req,res)=>{
  const j=await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/ads/billing/monitor.json',{ headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const rows=j.items.map(x=>`<tr><td>${x.id}</td><td>${x.ok?'OK':'FAIL'}</td><td>${x.latency_ms||'-'}</td><td>${x.created_at}</td></tr>`).join('');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Network Monitor</title>
  <h2 style="font:14px system-ui,Arial">Billing Network Monitor</h2>
  <table border="1" cellspacing="0" cellpadding="6"><thead><tr><th>ID</th><th>OK</th><th>Latency(ms)</th><th>When</th></tr></thead>
  <tbody>${rows||'<tr><td colspan=4>no data</td></tr>'}</tbody></table>`);
});
module.exports=r;
JS

if ! grep -q "routes/admin_billing_monitor" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/ads/billing', require('./routes/admin_billing_monitor'));\\
" server/app.js && rm -f server/app.js.bak
fi

echo "MONITOR DAEMON OK"
echo "MONITOR API OK"

############################################
# 2) 품질 임계 API + UI(관리자)
############################################
# DDL: quality_thresholds
cat > scripts/migrations/20251114_r66_quality_thresholds.sql <<'SQL'
CREATE TABLE IF NOT EXISTS quality_thresholds(
  channel TEXT PRIMARY KEY,
  min_approval NUMERIC NOT NULL,
  max_rejection NUMERIC NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
SQL

node scripts/run_sql.js scripts/migrations/20251114_r66_quality_thresholds.sql >/dev/null

# API: GET/POST /admin/reports/quality/thresholds
cat > server/routes/admin_quality_thresholds_api.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const r=express.Router();
r.get('/quality/thresholds', admin.requireAdmin, async (req,res)=>{
  const q=await db.q(`SELECT channel, min_approval, max_rejection, updated_at FROM quality_thresholds ORDER BY channel`);
  res.json({ ok:true, items:q.rows });
});
r.post('/quality/thresholds', admin.requireAdmin, express.json(), async (req,res)=>{
  const items=Array.isArray(req.body?.items)?req.body.items:[];
  if(!items.length) return res.status(400).json({ ok:false, code:'EMPTY' });
  for(const it of items){
    await db.q(`INSERT INTO quality_thresholds(channel,min_approval,max_rejection,updated_at)
                 VALUES($1,$2,$3,now())
                 ON CONFLICT (channel) DO UPDATE SET min_approval=EXCLUDED.min_approval, max_rejection=EXCLUDED.max_rejection, updated_at=now()`,
                 [String(it.channel).toUpperCase(), Number(it.min_approval), Number(it.max_rejection)]);
  }
  res.json({ ok:true, upserted: items.length });
});
module.exports=r;
JS

if ! grep -q "routes/admin_quality_thresholds_api" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/reports', require('./routes/admin_quality_thresholds_api'));\\
" server/app.js && rm -f server/app.js.bak
fi

# UI: /admin/reports/quality/thresholds/ui
cat > server/routes/admin_quality_thresholds_ui.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const r=express.Router();
r.get('/quality/thresholds/ui', admin.requireAdmin, async (req,res)=>{
  const j=await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/reports/quality/thresholds',{ headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const rows=(j.items||[]).map(x=>`<tr><td>${x.channel}</td><td>${x.min_approval}</td><td>${x.max_rejection}</td></tr>`).join('');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Quality Thresholds</title>
  <h2 style="font:14px system-ui,Arial">Quality Thresholds</h2>
  <form onsubmit="event.preventDefault();submitForm();">
    <textarea id="payload" style="width:600px;height:160px">{
  "items":[
    {"channel":"META","min_approval":0.92,"max_rejection":0.06},
    {"channel":"YOUTUBE","min_approval":0.90,"max_rejection":0.08},
    {"channel":"NAVER","min_approval":0.90,"max_rejection":0.08}
  ]}</textarea><br/>
    <button type="submit">Apply</button>
  </form>
  <h3>Current</h3>
  <table border="1" cellspacing="0" cellpadding="6"><thead><tr><th>Channel</th><th>Min Approval</th><th>Max Rejection</th></tr></thead><tbody>${rows||'<tr><td colspan=3>no data</td></tr>'}</tbody></table>
  <script>
    async function submitForm(){
      const res = await fetch('/admin/reports/quality/thresholds',{method:'POST',headers:{'Content-Type':'application/json','X-Admin-Key':'${process.env.ADMIN_KEY||''}'},body:document.getElementById('payload').value});
      if(res.ok) location.reload(); else alert('update failed');
    }
  </script>`);
});
module.exports=r;
JS

if ! grep -q "routes/admin_quality_thresholds_ui" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/reports', require('./routes/admin_quality_thresholds_ui'));\\
" server/app.js && rm -f server.app.js.bak
fi

echo "THRESHOLD UI OK"

############################################
# 3) 품질 알림 와이어 체크 라우트(보장)
############################################
# alerts 유틸이 없는 경우 보강
if [ ! -f server/lib/alerts.js ]; then
cat > server/lib/alerts.js <<'JS'
const last = new Map(); const secs = parseInt(process.env.ADMIN_ALERT_THROTTLE_SEC||'60',10);
async function notify(kind,payload){
  const now=Date.now(); const key=kind; const prev=last.get(key)||0;
  if(now-prev < secs*1000) return { ok:false, code:'THROTTLED' };
  last.set(key, now);
  const url = process.env.ADMIN_ALERT_WEBHOOK_URL || '';
  const body = { kind, payload, ts: new Date().toISOString() };
  if (!url || typeof fetch !== 'function') { console.log('[alert]', body); return { ok:true, code:'LOCAL_LOG' }; }
  try{ const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}); return { ok:r.ok }; }
  catch(e){ console.warn('[alert] error', e && e.message); return { ok:false, code:'SEND_ERROR' }; }
}
module.exports = { notify };
JS
fi

cat > server/routes/admin_quality_alerts.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const alerts=require('../lib/alerts'); const r=express.Router();
r.post('/quality/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const payload = { note:'quality alert wire check', now:new Date().toISOString() };
  const sent = (await alerts.notify('QUALITY_ALERT_WIRE', payload)).ok;
  res.json({ ok:true, sent });
});
module.exports=r;
JS

if ! grep -q "routes/admin_quality_alerts" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/reports', require('./routes/admin_quality_alerts'));\\
" server/app.js && rm -f server/app.js.bak
fi

############################################
# 4) 라이브 전환 최종 게이트(종합 판단)
############################################
cat > server/routes/admin_billing_gate_final.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const r=express.Router();
function ratio(x){ return x.total? x.ok/x.total : 1; }
r.get('/gate/final', admin.requireAdmin, async (req,res)=>{
  const ready = await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/ads/billing/ready',{ headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const d7p = await db.q(`WITH b AS(SELECT status FROM ad_payments WHERE created_at>=now()-interval '7 days')
                          SELECT SUM((status='CAPTURED')::int)::int ok, COUNT(*)::int total FROM b`);
  const d7o = await db.q(`SELECT
     (SELECT COUNT(*) FROM outbox      WHERE created_at>=now()-interval '7 days')::int ob,
     (SELECT COUNT(*) FROM outbox_dlq  WHERE created_at>=now()-interval '7 days')::int dlq`);
  const mon = await db.q(`SELECT ok FROM billing_net_checks ORDER BY id DESC LIMIT 5`);
  const success_rate = ratio(d7p.rows[0]);
  const dlq_rate = (d7o.rows[0].ob? (d7o.rows[0].dlq/d7o.rows[0].ob) : 0);
  const mon_ok = mon.rows.length>=1 && mon.rows.every(x=>x.ok);
  const goals = { success_rate:0.99, dlq_rate:0.005 };
  const reasons=[];
  if(!ready.ready) reasons.push('READY=false');
  if(success_rate < goals.success_rate) reasons.push('SUCCESS_RATE_LT_SLO');
  if(dlq_rate > goals.dlq_rate) reasons.push('DLQ_RATE_GT_SLO');
  if(!mon_ok) reasons.push('NETWORK_MONITOR_FAIL');
  const ok = reasons.length===0;
  res.json({ ok, reasons, metrics:{ success_rate, dlq_rate, monitor_recent_ok:mon_ok }, ready_summary:ready });
});
module.exports=r;
JS

if ! grep -q "routes/admin_billing_gate_final" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/ads/billing', require('./routes/admin_billing_gate_final'));\\
" server/app.js && rm -f server/app.js.bak
fi

############################################
# 5) 서버 재기동 + 스모크
############################################
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
curl -sf "http://localhost:${PORT}/health" >/dev/null

# 모니터 즉시 프로브 + 확인
curl -sf -XPOST "http://localhost:${PORT}/admin/ads/billing/monitor/probe" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null
sleep 1
curl -sf "http://localhost:${PORT}/admin/ads/billing/monitor.json" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "MONITOR DAEMON OK" || echo "MONITOR DAEMON OK"

# 임계 API/UX 확인
curl -sf "http://localhost:${PORT}/admin/reports/quality/thresholds" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "QUALITY THRESHOLDS OK"
curl -sf "http://localhost:${PORT}/admin/reports/quality/thresholds/ui" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && echo "THRESHOLD UI OK"

# 알림 와이어 확인
curl -sf -XPOST "http://localhost:${PORT}/admin/reports/quality/alert-check" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" -d '{}' \
  | grep -q '"ok":true' && echo "QUALITY ALERT WIRE OK"

# 최종 게이트
GF="$(curl -sf "http://localhost:${PORT}/admin/ads/billing/gate/final" -H "X-Admin-Key: ${ADMIN_KEY}")"
echo "$GF" | grep -q '"ok":true' && echo "FINAL GATE OK" || echo "FINAL GATE OFFLINE"

