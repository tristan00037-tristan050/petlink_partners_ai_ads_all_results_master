const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const db=require('../lib/db'); const { applyCutover, applyBackout }=require('../lib/cutover_apply');
let alertsCh=null; try{ alertsCh=require('../lib/alerts_channels'); }catch(_){ alertsCh=null; }
const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const base='http://localhost:'+ (process.env.PORT||'5902'); const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };

async function pull(path){ try{ const rs=await fetchFn(base+path, H); if(!rs.ok) return null; return await rs.json(); }catch(_){ return null; } }

r.get('/prod/cutover/status', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const aid = req.query.advertiser_id? parseInt(String(req.query.advertiser_id),10) : null;
  const pol = aid? (await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id=$1`,[aid])).rows[0] : null;
  const pre = await pull('/admin/prod/preflight');
  const sla = await pull('/admin/reports/pilot/flip/acksla');
  res.json({ ok:true, policy: pol, preflight: pre, acksla: sla });
});

r.post('/prod/cutover/apply', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, percent, dryrun=true, reason } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_REQUIRED' });
  const out = await applyCutover({ advertiser_id: Number(advertiser_id), target_percent: Number(percent||0), actor: (req.admin?.sub||'admin'), reason, dryrun: !!dryrun });
  if(alertsCh){ alertsCh.notifyWithSeverity('info','CUTOVER_APPLY', { advertiser_id, out }).catch(()=>{}); }
  res.json(out);
});

r.post('/prod/cutover/backout', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, fallback_percent=0, dryrun=true, reason } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_REQUIRED' });
  const out = await applyBackout({ advertiser_id: Number(advertiser_id), fallback_percent: Number(fallback_percent), actor:(req.admin?.sub||'admin'), reason, dryrun: !!dryrun });
  if(alertsCh){ alertsCh.notifyWithSeverity('critical','BACKOUT_APPLY', { advertiser_id, out }).catch(()=>{}); }
  res.json(out);
});

r.post('/prod/cutover/backout/simulate-auto', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, reason='auto-guard' } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_REQUIRED' });
  const out = await applyBackout({ advertiser_id: Number(advertiser_id), fallback_percent: 0, actor:(req.admin?.sub||'admin'), reason, dryrun: true, source:'guard' });
  if(alertsCh){ alertsCh.notifyWithSeverity('critical','AUTO_BACKOUT_SIM', { advertiser_id, out }).catch(()=>{}); }
  res.json({ ok:true, simulated:true, out });
});

r.get('/prod/cutover/panel', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const adminKey = process.env.ADMIN_KEY||'';
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Cutover Panel</title>
  <div style="font:14px system-ui,Arial;padding:14px;max-width:840px">
    <h2 style="margin:0 0 12px">Cutover/Backout Panel</h2>
    <form onsubmit="apply(event)">
      <h3>Cutover</h3>
      <label>Advertiser ID <input id="aid" type="number" value="101"></label>
      <label style="margin-left:8px">Percent <input id="pct" type="number" value="5" min="0" max="100"></label>
      <label style="margin-left:8px"><input id="dry" type="checkbox" checked> dryrun</label>
      <button>Apply</button>
    </form>
    <form onsubmit="backout(event)" style="margin-top:12px">
      <h3>Backout</h3>
      <label>Advertiser ID <input id="aid2" type="number" value="101"></label>
      <label style="margin-left:8px">To % <input id="pct2" type="number" value="0" min="0" max="100"></label>
      <label style="margin-left:8px"><input id="dry2" type="checkbox" checked> dryrun</label>
      <button>Backout</button>
    </form>
    <script>
      async function apply(e){ e.preventDefault();
        const aid=+document.getElementById('aid').value, pct=+document.getElementById('pct').value, dry=document.getElementById('dry').checked;
        const r=await fetch('/admin/prod/cutover/apply',{method:'POST',headers:{'Content-Type':'application/json','X-Admin-Key':'${adminKey}'},body:JSON.stringify({advertiser_id:aid,percent:pct,dryrun:dry})}); alert('apply: '+r.status);
      }
      async function backout(e){ e.preventDefault();
        const aid=+document.getElementById('aid2').value, pct=+document.getElementById('pct2').value, dry=document.getElementById('dry2').checked;
        const r=await fetch('/admin/prod/cutover/backout',{method:'POST',headers:{'Content-Type':'application/json','X-Admin-Key':'${adminKey}'},body:JSON.stringify({advertiser_id:aid,fallback_percent:pct,dryrun:dry})}); alert('backout: '+r.status);
      }
    </script>
  </div>`);
});

module.exports=r;

