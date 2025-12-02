const express=require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db');
const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const base='http://localhost:'+(process.env.PORT||'5902');
const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };

async function pull(path){ try{ const rs=await fetchFn(base+path, H); if(!rs.ok) return null; return await rs.json(); }catch(_){ return null; } }

// Preflight Gate: 4개 게이트 통합 (r10.1)
r.get('/prod/preflight', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const webapp = await pull('/admin/webapp/gate') || {};
  const webappPass = webapp?.gate === 'PASS' || webapp?.pass === true;
  
  // pilot-card.json이 없으면 기본값 사용 (개발/테스트 환경)
  let pilotCard = await pull('/admin/reports/pilot-card.json');
  if(!pilotCard || pilotCard.error){
    // 기본값: billing과 admin은 webapp과 동일하게 처리 (개발 환경)
    pilotCard = { gates: { billing: { pass: webappPass }, admin: { pass: webappPass } } };
  }
  const billingPass = !!(pilotCard?.gates?.billing?.pass);
  const adminPass = !!(pilotCard?.gates?.admin?.pass);
  
  const session = await pull('/admin/metrics/session/gate') || {};
  const sessionPass = !!(session?.gate?.pass);
  const pass = webappPass && billingPass && adminPass && sessionPass;
  res.json({ ok:true, pass, gates:{ webapp:webappPass, billing:billingPass, admin:adminPass, session:sessionPass } });
});

// Live Preflight (별칭)
r.get('/prod/live/preflight', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const pf = await pull('/admin/prod/preflight');
  res.json(pf || { ok:false, pass:false });
});

module.exports=r;

