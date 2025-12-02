const express = require('express');
const fetchFn = (global.fetch || require('node-fetch'));
const admin = (require('../mw/admin_gate')||require('../mw/admin'));
const sched = require('../bootstrap/pilot_schedulers');
const r = express.Router();
const guard = (admin.requireAdminAny || admin.requireAdmin);
const base = 'http://localhost:'+ (process.env.PORT||'5902');
const AK = process.env.ADMIN_KEY||'';

r.get('/pilot/scheduler/status', guard, async (req,res)=>{
  const s = await sched.status().catch(()=>({ok:false}));
  res.json(s);
});

async function call(path){
  const r = await fetchFn(base+path, { method:'POST', headers:{'X-Admin-Key':AK,'Content-Type': 'application/json'} });
  try{ return await r.json(); }catch(_){ return {ok:false}; }
}

r.post('/pilot/scheduler/run-weekly-now', guard, async (req,res)=> res.json(await call('/admin/reports/pilot/autopush/run-weekly')));
r.post('/pilot/scheduler/run-monthly-now', guard, async (req,res)=> res.json(await call('/admin/reports/pilot/autopush/run-monthly')));

module.exports = r;

