const db = require('../lib/db');
const pick = require('../lib/billing/factory');
const { performance } = require('node:perf_hooks');

async function probeOnce(){
  const getAdapter = pick();
  const adapter = typeof getAdapter === 'function' ? getAdapter() : getAdapter;
  let ok=false, latency=0, detail='';
  const t0 = performance.now();
  try{
    const p = adapter && adapter.__probeToken ? await adapter.__probeToken() : { has_token:false, offline:true };
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
