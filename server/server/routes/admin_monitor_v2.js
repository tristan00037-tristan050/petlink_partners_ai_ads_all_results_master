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
