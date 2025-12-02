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
