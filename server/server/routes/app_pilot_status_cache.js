const express=require('express');
const fetchFn=(global.fetch||require('node-fetch'));
const { withCache } = require('../lib/cache60');
const { appCORS } = (function(){ try { return require('../mw/cors_split'); } catch(e){ return {}; } })();
const r=express.Router();

async function fetchStatus(){
  try{
    const res = await fetchFn('http://localhost:'+(process.env.PORT||'5902')+'/app/pilot/status.json', { headers:{}, redirect:'follow' });
    if(!res.ok) return { ok:false, go:false, cached:false };
    const j = await res.json(); 
    return Object.assign({ cached:true }, j);
  }catch(_){ return { ok:false, go:false, cached:false, error:'upstream-failed' }; }
}
r.get('/app/pilot/status.cached.json', appCORS||((req,res,next)=>next()), withCache(60, async()=> await fetchStatus()));
module.exports = r;
