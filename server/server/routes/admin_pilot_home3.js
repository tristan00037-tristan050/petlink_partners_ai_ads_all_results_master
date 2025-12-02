const express=require('express');
const fetchFn=(global.fetch||require('node-fetch'));
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

async function pull(path){
  try{
    const r=await fetchFn('http://localhost:'+ (process.env.PORT||'5902') + path,{headers:{'X-Admin-Key':process.env.ADMIN_KEY||''}});
    if(!r.ok) return null; return await r.json();
  }catch(_){ return null; }
}
function badge(go){
  const color = go? '#0a5': '#a00';
  const label = go? 'GO' : 'HOLD';
  return `<div id="pilot-badge" style="display:inline-flex;align-items:center;gap:8px;border:1px solid ${color};color:${color};padding:6px 10px;border-radius:999px;font:14px/1 system-ui,Arial">
    <span style="font-weight:700">${label}</span><span style="font-size:12px;color:#555">Pilot</span>
    <a href="/admin/reports/pilot-card" style="margin-left:8px;text-decoration:none;color:#06c">자세히</a>
  </div>`;
}

r.get('/reports/home-fast3', adminCORS||((req,res,next)=>next()), guard, async (req,res)=>{
  const t0=Date.now();
  const card = await pull('/admin/reports/pilot-card.json');
  const go = !!card?.overall?.go;
  const ms = Date.now()-t0;
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.setHeader('X-Gen-Ms', String(ms));
  const b=(p)=>`<span style="display:inline-block;border:1px solid ${p?'#0a5':'#a00'};color:${p?'#0a5':'#a00'};padding:2px 8px;border-radius:999px;font-weight:700">${p?'PASS':'HOLD'}</span>`;
  res.end(`<!doctype html><meta charset="utf-8"><title>Pilot Home</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <div style="margin:0 0 12px">${badge(go)}</div>
    <h2 style="margin:0 0 8px">Pilot Go/No‑Go ${b(go)}</h2>
    <div style="display:flex;gap:12px;flex-wrap:wrap">
      <div style="border:1px solid #ddd;border-radius:8px;padding:10px;min-width:220px"><b>WebApp</b> ${b(card?.gates?.webapp?.pass)}</div>
      <div style="border:1px solid #ddd;border-radius:8px;padding:10px;min-width:220px"><b>Billing(SBX)</b> ${b(card?.gates?.billing?.pass)}</div>
      <div style="border:1px solid #ddd;border-radius:8px;padding:10px;min-width:220px"><b>Admin 최소</b> ${b(card?.gates?.admin?.pass)}</div>
      <div style="border:1px solid #ddd;border-radius:8px;padding:10px;min-width:220px"><b>Session</b> ${b(card?.gates?.session?.pass)}</div>
    </div>
    <div style="margin-top:12px;color:#666">gen=${ms}ms</div>
  </div>`);
});

module.exports=r;

