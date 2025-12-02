#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/lib server/routes server/openapi evidence

export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need curl; need psql
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }

# [0] 전제 확인(핵심 라우트)
test -f server/routes/ads_billing.js || { echo "[ERR] server/routes/ads_billing.js not found"; exit 1; }

# [1] 5분 버킷 시계열 집계용 뷰(멱등)
cat > scripts/migrations/20251113_r610_timeseries.sql <<'SQL'
-- 24h/5m 버킷 집계에 사용할 뷰(존재 시 재생성 안함)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='v_payments_5m') THEN
    CREATE VIEW v_payments_5m AS
    SELECT
      to_timestamp(floor(extract(epoch FROM created_at)/300)*300) AT TIME ZONE 'UTC' AS ts5,
      SUM(CASE WHEN status='CAPTURED'   THEN 1 ELSE 0 END)::int AS captured,
      SUM(CASE WHEN status='AUTHORIZED' THEN 1 ELSE 0 END)::int AS authorized,
      SUM(CASE WHEN status='FAILED'     THEN 1 ELSE 0 END)::int AS failed,
      COUNT(*)::int AS total
    FROM ad_payments
    GROUP BY 1;

    -- outbox_dlq 뷰가 없으면 생성 (dlq 테이블 기반)
    IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='outbox_dlq') 
       AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dlq') THEN
      CREATE VIEW outbox_dlq AS 
        SELECT id, topic, payload, reason, COALESCE(failed_at, now()) AS created_at FROM dlq;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='v_outbox_dlq_5m') THEN
      CREATE VIEW v_outbox_dlq_5m AS
      SELECT
        to_timestamp(floor(extract(epoch FROM created_at)/300)*300) AT TIME ZONE 'UTC' AS ts5,
        COUNT(*)::int AS dlq
      FROM outbox_dlq
      GROUP BY 1;
    END IF;

    -- 선택 지표: PM 루프 계측(p95)
    CREATE VIEW v_ops_loop_5m AS
    SELECT
      to_timestamp(floor(extract(epoch FROM created_at)/300)*300) AT TIME ZONE 'UTC' AS ts5,
      percentile_disc(0.95) WITHIN GROUP (ORDER BY value)::int AS p95_ms
    FROM ad_ops_metrics
    WHERE metric='PM_LOOP_MS'
    GROUP BY 1;
  END IF;
END$$;
SQL

node scripts/run_sql.js scripts/migrations/20251113_r610_timeseries.sql >/dev/null

# [2] 모니터 API(JSON) + 대시보드(HTML)
cat > server/routes/admin_monitor_v2.js <<'JS'
const express=require('express');
const admin=require('../mw/admin');
const db=require('../lib/db');
const r=express.Router();

/** GET /admin/ads/billing/monitor.json?hours=24 */
r.get('/ads/billing/monitor.json', admin.requireAdmin, async (req,res)=>{
  const hours=Math.max(1,Math.min(72,parseInt(req.query.hours||'24',10)));
  const from=`now()-interval '${hours} hours'`;

  const pay = await db.q(`
    WITH s AS (
      SELECT generate_series(${from}::timestamptz, now(), interval '5 minutes') AS ts5
    )
    SELECT s.ts5,
           COALESCE(p.captured,0)::int captured,
           COALESCE(p.authorized,0)::int authorized,
           COALESCE(p.failed,0)::int failed,
           COALESCE(p.total,0)::int total,
           COALESCE(d.dlq,0)::int dlq,
           COALESCE(o.p95_ms, NULL)::int p95_ms
    FROM s
    LEFT JOIN v_payments_5m p ON p.ts5 = s.ts5
    LEFT JOIN v_outbox_dlq_5m d ON d.ts5 = s.ts5
    LEFT JOIN v_ops_loop_5m o ON o.ts5 = s.ts5
    ORDER BY s.ts5 ASC
  `);

  // 집계율
  const agg = await db.q(`
    SELECT
      SUM(captured)::int captured, SUM(failed)::int failed, SUM(total)::int total,
      CASE WHEN SUM(total)=0 THEN 1.0 ELSE ROUND(SUM(captured)::numeric / NULLIF(SUM(total),0), 4) END AS success_rate,
      CASE WHEN SUM(total)=0 THEN 0.0 ELSE ROUND(SUM(failed)::numeric / NULLIF(SUM(total),0), 4) END AS fail_rate,
      CASE WHEN SUM(total)=0 THEN 0.0 ELSE ROUND(SUM(dlq)::numeric / GREATEST(SUM(total),1), 4) END AS dlq_rate
    FROM (
      SELECT COALESCE(p.captured,0) captured, COALESCE(p.failed,0) failed, COALESCE(p.total,0) total, COALESCE(d.dlq,0) dlq
      FROM v_payments_5m p
      LEFT JOIN v_outbox_dlq_5m d ON d.ts5=p.ts5
      WHERE p.ts5 >= ${from}::timestamptz
    ) x
  `);

  res.json({ ok:true, hours, series: pay.rows, summary: agg.rows[0]||{} });
});

/** GET /admin/ads/billing/monitor (HTML) */
r.get('/ads/billing/monitor', admin.requireAdmin, async (req,res)=>{
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Billing Monitor</title>
  <style>body{font:14px system-ui,Arial;margin:16px} .k{display:inline-block;border:1px solid #ddd;padding:12px;border-radius:6px;margin-right:8px}</style>
  <h2>Billing Monitor (5m buckets, last 24h)</h2>
  <div id="kpis"></div>
  <canvas id="c1" width="1200" height="260"></canvas>
  <canvas id="c2" width="1200" height="140"></canvas>
  <script>
  async function q(p){return (await fetch(p,{headers:{'X-Admin-Key':'${process.env.ADMIN_KEY||''}'}})).json()}
  const j = await q('/admin/ads/billing/monitor.json?hours=24');
  const pct = (x)=> ((Math.round((Number(x||0))*10000)/100)+'%');
  const k = j.summary||{};
  document.getElementById('kpis').innerHTML =
    '<div class="k"><div>Success Rate</div><b>'+pct(k.success_rate)+'</b></div>'+
    '<div class="k"><div>Fail Rate</div><b>'+pct(k.fail_rate)+'</b></div>'+
    '<div class="k"><div>DLQ Rate</div><b>'+pct(k.dlq_rate)+'</b></div>';

  function drawLine(canvasId, series, fields, maxY){
    const c=document.getElementById(canvasId), g=c.getContext('2d');
    const W=c.width, H=c.height, L=40, R=10, B=20, T=10;
    g.clearRect(0,0,W,H);
    g.strokeStyle='#000'; g.beginPath(); g.moveTo(L,T); g.lineTo(L,H-B); g.lineTo(W-R,H-B); g.stroke();
    const n=series.length; if(!n) return;
    const xs=(W-L-R)/Math.max(n-1,1);
    const colors=['#2c7','#e33','#999','#06f']; // captured, failed, dlq, p95
    fields.forEach((f,fi)=>{
      g.beginPath(); g.strokeStyle=colors[fi%colors.length];
      series.forEach((row,i)=>{
        const v = Math.max(0, Number(row[f]||0));
        const x = L + i*xs;
        const y = H-B - (maxY? (v/maxY)*(H-B-T) : 0);
        if(i===0) g.moveTo(x,y); else g.lineTo(x,y);
      });
      g.stroke();
    });
  }
  // 최대치 계산(왜곡 방지)
  const maxCount = Math.max(1, ...j.series.map(x=>Math.max(x.captured||0,x.failed||0,x.dlq||0)));
  drawLine('c1', j.series, ['captured','failed','dlq'], maxCount);
  const maxP95 = Math.max(1, ...j.series.map(x=>x.p95_ms||0));
  drawLine('c2', j.series, ['p95_ms'], maxP95);
  </script>`);
});

module.exports=r;
JS

if ! grep -q "routes/admin_monitor_v2" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin', require('./routes/admin_monitor_v2'));\\
" server/app.js && rm -f server/app.js.bak
fi

# [3] Evidence v3 스크립트 + 라우트
cat > scripts/generate_live_evidence_v3.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-5902}"
ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
STAMP="$(date +%Y%m%d_%H%M%S)"
DIR="evidence/live_proof_v3_${STAMP}"
mkdir -p "${DIR}/api" "${DIR}/db" "${DIR}/openapi" || true

curl -sf "http://localhost:${PORT}/health" > "${DIR}/api/health.json" || true
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/gate/final" > "${DIR}/api/final_check.json" || true
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/monitor.json?hours=24" > "${DIR}/api/monitor_24h.json" || true
curl -sf "http://localhost:${PORT}/openapi_ops_live.yaml" > "${DIR}/openapi/ops_live.yaml" || true
curl -sf "http://localhost:${PORT}/openapi_quality.yaml" > "${DIR}/openapi/quality.yaml" || true

psql "${DATABASE_URL}" -c "COPY (SELECT * FROM ad_invoices ORDER BY id DESC LIMIT 200) TO STDOUT WITH CSV HEADER" > "${DIR}/db/ad_invoices.csv" || true
psql "${DATABASE_URL}" -c "COPY (SELECT * FROM ad_payments ORDER BY id DESC LIMIT 200) TO STDOUT WITH CSV HEADER" > "${DIR}/db/ad_payments.csv" || true
psql "${DATABASE_URL}" -c "COPY (SELECT * FROM audit_logs ORDER BY id DESC LIMIT 200) TO STDOUT WITH CSV HEADER" > "${DIR}/db/audit_logs.csv" || true
psql "${DATABASE_URL}" -c "COPY (SELECT id,topic,status,created_at FROM outbox WHERE topic LIKE 'AD_BILLING_%' ORDER BY id DESC LIMIT 500) TO STDOUT WITH CSV HEADER" > "${DIR}/db/outbox_events.csv" || true
tail -n 500 .petlink.out > "${DIR}/petlink_tail.log" || true

tar -czf "${DIR}.tgz" -C evidence "$(basename "${DIR}")"
echo "${DIR}.tgz"
BASH

chmod +x scripts/generate_live_evidence_v3.sh

cat > server/routes/admin_evidence_v3.js <<'JS'
const express=require('express');
const admin=require('../mw/admin'); const { execSync }=require('child_process');
const r=express.Router();
r.post('/ads/billing/live/evidence/export/v3', admin.requireAdmin, async (req,res)=>{
  try{
    const out = execSync('bash scripts/generate_live_evidence_v3.sh', { encoding:'utf8' }).trim();
    res.json({ ok:true, file: out });
  }catch(e){ res.status(500).json({ ok:false, code:'EVIDENCE_V3_FAIL', err: String(e.message||e) }); }
});
module.exports=r;
JS

if ! grep -q "routes/admin_evidence_v3" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin', require('./routes/admin_evidence_v3'));\\
" server/app.js && rm -f server.app.js.bak
fi

# [4] OpenAPI(모니터/증빙 v3)
cat > server/openapi/monitor_v2.yaml <<'YAML'
openapi: 3.0.3
info: { title: Billing Monitor v2, version: "r6.10" }
paths:
  /admin/ads/billing/monitor.json: { get: { summary: 5m buckets (24h), responses: { '200': { description: OK } } } }
  /admin/ads/billing/monitor:     { get: { summary: HTML dashboard,     responses: { '200': { description: OK } } } }
  /admin/ads/billing/live/evidence/export/v3: { post: { summary: Export live proof bundle v3, responses: { '200': { description: OK } } } }
YAML

if ! grep -q "openapi/monitor_v2.yaml" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.get('/openapi_monitor_v2.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','monitor_v2.yaml')));\\
" server.app.js && rm -f server/app.js.bak
fi

# [5] 서버 재기동
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
curl -sf "http://localhost:${PORT}/health" >/dev/null || { echo "[ERR] server not healthy"; exit 1; }

# [6] 스모크
sleep 2
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/monitor.json?hours=24" \
  | grep -q '"ok":true' && echo "MONITOR JSON OK"
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/monitor" >/dev/null \
  && echo "MONITOR UI OK"
curl -sf -XPOST -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/live/evidence/export/v3" \
  | grep -q '"ok":true' && echo "EVIDENCE V3 OK"
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/gate/final" \
  | grep -q '"ok":true' && echo "FINAL GATE RECHECK OK"

echo "R610 DONE"
