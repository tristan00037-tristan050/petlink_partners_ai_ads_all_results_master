const express=require('express');
const fetchFn=(global.fetch||require('node-fetch'));
let requireAdminAny; try{ requireAdminAny = require('../mw/admin_gate').requireAdminAny; }catch(e){ requireAdminAny=null; }
const { adminCORS } = (function(){ try { return require('../mw/cors_split'); } catch(e){ return {}; } })();
const r=express.Router();
const guard=(req,res,next)=> (requireAdminAny ? requireAdminAny(req,res,next) :
  (req.get('X-Admin-Key')===(process.env.ADMIN_KEY||'') ? next() : res.status(401).json({ok:false,code:'ADMIN_AUTH_REQUIRED'})));
r.get('/home-fast', adminCORS||((req,res,next)=>next()), guard, async (req,res)=>{
  let j={ ok:false }; 
  try{
    const resp = await fetchFn('http://localhost:'+(process.env.PORT||'5902')+'/admin/reports/home.json',{ headers:{'X-Admin-Key':process.env.ADMIN_KEY||''}});
    j = await resp.json();
  }catch(_){}
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Pilot Home (Fast)</title>
  <script>window.__PILOT_HOME__=${JSON.stringify(j)};</script>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2 style="margin-top:0">Pilot Home (Fast)</h2>
    <pre id="out" style="white-space:pre-wrap;background:#f8f8f8;padding:12px;border-radius:6px"></pre>
  </div>
  <script>
    (function(){ document.getElementById('out').textContent = JSON.stringify(window.__PILOT_HOME__, null, 2); })();
  </script>`);
});

module.exports = r;
