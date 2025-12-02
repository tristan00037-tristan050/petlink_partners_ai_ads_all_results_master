const express=require('express');
const db=require('../lib/db');
const fetchFn=(global.fetch||require('node-fetch'));
const { withCache } = require('../lib/cache60');
let requireAdminAny; try{ requireAdminAny = require('../mw/admin_gate').requireAdminAny; }catch(e){ requireAdminAny=null; }
const { adminCORS } = (function(){ try { return require('../mw/cors_split'); } catch(e){ return {}; } })();
const r=express.Router();
const guard=(req,res,next)=> (requireAdminAny ? requireAdminAny(req,res,next) :
  (req.get('X-Admin-Key')===(process.env.ADMIN_KEY||'') ? next() : res.status(401).json({ok:false,code:'ADMIN_AUTH_REQUIRED'})));

async function weeklyPayments(days=56){
  try{
    const q = await db.q(`
      WITH b AS (
        SELECT date_trunc('week', created_at) AS wk, status
        FROM ad_payments
        WHERE created_at >= now() - ($1||' days')::interval
      )
      SELECT wk::date AS bucket,
             SUM((status='CAPTURED')::int)::int AS ok,
             SUM((status='FAILED')::int)::int AS fail,
             COUNT(*)::int AS total
      FROM b GROUP BY 1 ORDER BY 1
    `,[days]);
    return q.rows.map(x=>({ bucket:String(x.bucket), ok:+x.ok||0, fail:+x.fail||0, total:+x.total||0,
      success_rate: (+x.total? (+x.ok/+x.total):1) }));
  }catch(_){ return []; }
}
async function weeklyAutoApprove(days=56){
  try{
    const q = await db.q(`
      WITH b AS (
        SELECT date_trunc('week', created_at) AS wk,
               COALESCE((flags->>'final')::text,'') AS final,
               EXTRACT(EPOCH FROM (approved_at - created_at)) AS lead
        FROM ad_creatives
        WHERE created_at >= now() - ($1||' days')::interval
      )
      SELECT wk::date AS bucket,
             SUM((final='approved')::int)::int AS approved,
             COUNT(*)::int AS total,
             SUM(CASE WHEN final='approved' AND lead IS NOT NULL AND lead<=300 THEN 1 ELSE 0 END)::int AS under5m
      FROM b GROUP BY 1 ORDER BY 1
    `,[days]);
    return q.rows.map(x=>({ bucket:String(x.bucket),
      auto_rate: (+x.total? (+x.approved/+x.total):1),
      under5m_rate: (+x.total? (+x.under5m/+x.total):1),
      total:+x.total||0
    }));
  }catch(_){ return []; }
}
async function weeklySessionP95(days=56){
  try{
    const q = await db.q(`
      WITH raw AS (
        SELECT date_trunc('week', created_at) AS wk,
               ms AS lat
        FROM session_events
        WHERE created_at >= now() - ($1||' days')::interval
          AND kind IN ('refresh_ok','refresh_fail')
          AND ms IS NOT NULL
      )
      SELECT wk::date AS bucket,
             percentile_disc(0.95) WITHIN GROUP (ORDER BY lat) AS p95_ms
      FROM raw WHERE lat IS NOT NULL GROUP BY 1 ORDER BY 1
    `,[days]);
    return q.rows.map(x=>({ bucket:String(x.bucket), p95_ms: Number(x.p95_ms||0) }));
  }catch(_){ return []; }
}
async function monthlyPayments(months=6){
  try{
    const q=await db.q(`
      WITH b AS(
        SELECT date_trunc('month', created_at) AS mk, status
        FROM ad_payments WHERE created_at >= now() - ($1||' months')::interval
      )
      SELECT mk::date AS bucket, SUM((status='CAPTURED')::int)::int ok,
             SUM((status='FAILED')::int)::int fail, COUNT(*)::int total
      FROM b GROUP BY 1 ORDER BY 1
    `,[months]);
    return q.rows.map(x=>({ bucket:String(x.bucket), ok:+x.ok||0, fail:+x.fail||0, total:+x.total||0,
      success_rate:(+x.total? (+x.ok/+x.total):1) }));
  }catch(_){ return []; }
}

r.get('/pilot/trends.json', adminCORS||((req,res,next)=>next()), guard,
  withCache(60, async ()=>{
    const weekly = await weeklyPayments(56);
    const auto = await weeklyAutoApprove(56);
    const sess = await weeklySessionP95(56);
    const monthly = await monthlyPayments(6);
    return { ok:true, weekly, auto, sess, monthly };
}));

r.get('/pilot/trends', adminCORS||((req,res,next)=>next()), guard, async (req,res)=>{
  const j = await (await fetchFn('http://localhost:'+(process.env.PORT||'5902')+'/admin/reports/pilot/trends.json',
                                { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''}})).json();
  const spark = (arr, key, w=220, h=40)=>{
    const nums = (arr||[]).map(x=> Number(x[key]||0));
    if(!nums.length) return `<svg width="${w}" height="${h}"></svg>`;
    const min = Math.min(...nums), max = Math.max(...nums);
    const nx = i => (i/(nums.length-1))*(w-6)+3;
    const ny = v => h-3 - (max-min ? ((v-min)/(max-min))*(h-10) : 0);
    const pts = nums.map((v,i)=> `${nx(i)},${ny(v)}`).join(' ');
    return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
      <polyline fill="none" stroke="#666" stroke-width="1" points="${pts}"/>
    </svg>`;
  };
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Pilot Trends</title>
  <div style="font:14px system-ui,Arial;padding:16px;display:flex;gap:12px;flex-wrap:wrap">
    <div style="border:1px solid #ddd;border-radius:8px;padding:12px;min-width:260px">
      <h3 style="margin:0 0 6px">Weekly Success Rate</h3>
      ${spark(j.weekly,'success_rate')}
    </div>
    <div style="border:1px solid #ddd;border-radius:8px;padding:12px;min-width:260px">
      <h3 style="margin:0 0 6px">Weekly Auto-Approve</h3>
      ${spark(j.auto,'auto_rate')}
    </div>
    <div style="border:1px solid #ddd;border-radius:8px;padding:12px;min-width:260px">
      <h3 style="margin:0 0 6px">Weekly Session p95(ms)</h3>
      ${spark(j.sess,'p95_ms')}
    </div>
    <div style="border:1px solid #ddd;border-radius:8px;padding:12px;min-width:260px">
      <h3 style="margin:0 0 6px">Monthly Success Rate</h3>
      ${spark(j.monthly,'success_rate')}
    </div>
  </div>`);
});

module.exports = r;
