const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { rampRecent }=require('../lib/tv_kpis');
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/tv/ramp/json', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const m = req.query.minutes ? parseInt(String(req.query.minutes),10) : 15;
  const aid = req.query.advertiser_id? parseInt(String(req.query.advertiser_id),10) : null;
  const out=await rampRecent(m, aid);
  res.json(out);
});

r.get('/tv/ramp', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const out=await rampRecent(15, null);
  const pct=(x)=> ((Math.round(x*1000)/10)+'%');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>TV • Ramp</title>
  <div style="font:24px system-ui,Arial;padding:24px;background:#000;color:#fff">
    <div style="font-weight:700;font-size:28px;margin-bottom:8px">Go‑Live TV — 15m</div>
    <div style="display:flex;gap:24px">
      <div>Attempts<br><b style="font-size:40px">${out.total||0}</b></div>
      <div>Live%<br><b style="font-size:40px">${pct(out.live_share||0)}</b></div>
      <div>Fail% (Live)<br><b style="font-size:40px">${pct(out.fail_rate||0)}</b></div>
      <div>Live Amt<br><b style="font-size:40px">${out.live_amount||0}</b></div>
    </div>
    <div style="margin-top:12px;font-size:14px;color:#aaa">auto-refresh every 10s</div>
  </div>
  <script>setTimeout(()=>location.reload(),10000);</script>`);
});

module.exports=r;

