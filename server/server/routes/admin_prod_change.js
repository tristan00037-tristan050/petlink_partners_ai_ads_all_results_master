const express=require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const db=require('../lib/db'); const { send }=require('../lib/change_notify');
const fetchFn=(global.fetch||require('node-fetch'));
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };
const base='http://localhost:'+(process.env.PORT||'5902');

async function pull(path){ try{ const rs=await fetchFn(base+path, H); if(!rs.ok) return null; return await rs.json(); }catch(_){ return null; } }

r.post('/prod/change/request', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const actor=req.admin?.sub||req.user?.sub||'admin';
  const { kind, payload, notes } = req.body||{};
  if(!kind || !payload) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const q=await db.q(`INSERT INTO prod_change_requests(kind,payload,created_by,notes) VALUES($1,$2,$3,$4) RETURNING *`,
                     [kind, payload, actor, notes||null]);
  await db.q(`INSERT INTO prod_change_events(req_id,actor,action,data) VALUES($1,$2,'CREATED',$3)`,
             [q.rows[0].id, actor, payload]);
  await send('CREATED', { id:q.rows[0].id, kind, actor, payload });
  res.json({ ok:true, item:q.rows[0] });
});

r.post('/prod/change/approve', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { id, approve, note, approver_id }=req.body||{};
  const actor=approver_id || req.admin?.sub || req.user?.sub || 'admin-approver';
  const cur=(await db.q(`SELECT * FROM prod_change_requests WHERE id=$1`,[id])).rows[0];
  if(!cur) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  if(cur.created_by && cur.created_by===actor) return res.status(403).json({ ok:false, code:'SEPARATION_OF_DUTIES' });
  if(approve!==true){ await db.q(`UPDATE prod_change_requests SET status='REJECTED', notes=$2 WHERE id=$1`,[id, note||null]);
    await db.q(`INSERT INTO prod_change_events(req_id,actor,action,data) VALUES($1,$2,'REJECTED',$3)`,[id, actor, {note}]);
    return res.json({ ok:true, rejected:true }); }
  const q=await db.q(`UPDATE prod_change_requests SET status='APPROVED', approved_by=$2, approved_at=now(), notes=COALESCE(notes,$3) WHERE id=$1 RETURNING *`,
                     [id, actor, note||null]);
  await db.q(`INSERT INTO prod_change_events(req_id,actor,action,data) VALUES($1,$2,'APPROVED',$3)`,[id, actor, {note}]);
  await send('APPROVED', { id, kind:q.rows[0].kind, approved_by:actor });
  res.json({ ok:true, item:q.rows[0] });
});

r.post('/prod/change/apply-dryrun', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const actor=req.admin?.sub||req.user?.sub||'admin'; const { id }=req.body||{};
  const cur=(await db.q(`SELECT * FROM prod_change_requests WHERE id=$1`,[id])).rows[0];
  if(!cur) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  if(cur.status!=='APPROVED') return res.status(409).json({ ok:false, code:'NOT_APPROVED' });

  // 효과 시뮬: 현재 게이트 스냅샷 + 적용 후 기대치(메시지)만 반환 (환경 변경 없음)
  const card = await pull('/admin/reports/pilot-card.json'); // r9.1
  const web  = await pull('/admin/webapp/gate');            // r8.9
  const sess = await pull('/admin/metrics/session/gate');   // r8.8
  const now  = { webapp_pass: !!(web?.pass ?? card?.gates?.webapp?.pass),
                 billing_pass: !!(card?.gates?.billing?.pass),
                 admin_pass: !!(card?.gates?.admin?.pass),
                 session_pass: !!(sess?.gate?.pass ?? card?.gates?.session?.pass) };
  const plan = { message: 'No env flip performed (dry-run only). Apply requires ops window.', requested: cur.payload };
  await db.q(`INSERT INTO prod_change_events(req_id,actor,action,data) VALUES($1,$2,'APPLY_DRYRUN',$3)`,[id, actor, { now, plan }]);
  await send('APPLY_DRYRUN', { id, actor, now, plan });
  res.json({ ok:true, now, plan });
});

r.get('/prod/change/requests', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const rows=(await db.q(`SELECT * FROM prod_change_requests ORDER BY id DESC LIMIT 200`)).rows;
  res.json({ ok:true, items: rows });
});

r.get('/prod/change/checklist', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const card = await pull('/admin/reports/pilot-card.json');
  const web  = await pull('/admin/webapp/gate');
  const sess = await pull('/admin/metrics/session/gate');
  const gate = {
    webapp:  !!(web?.pass ?? card?.gates?.webapp?.pass),
    billing: !!(card?.gates?.billing?.pass),
    admin:   !!(card?.gates?.admin?.pass),
    session: !!(sess?.gate?.pass ?? card?.gates?.session?.pass)
  };
  const pass = gate.webapp && gate.billing && gate.admin && gate.session;
  res.json({ ok:true, pass, gate, note:'Checklist is read-only; use /prod/prodgate for final readiness.' });
});

r.get('/prod/prodgate', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  // r10.1의 /admin/prod/preflight과 동등 수준의 최종 Gate
  const pf = await pull('/admin/prod/preflight'); // r10.1
  res.json({ ok:true, pass: !!(pf?.pass ?? pf?.ok), snapshot: pf||{} });
});

module.exports = r;

