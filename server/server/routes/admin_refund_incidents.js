const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { scanAndOpenIncidents }=require('../lib/refund_sla_watch'); const db=require('../lib/db');
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.post('/ledger/refund/incidents/watch/run', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  const out=await scanAndOpenIncidents(parseInt(process.env.REFUND_SLA_MINUTES||'120',10));
  res.json({ ok:true, ...out });
});
r.get('/ledger/refund/incidents', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  const q=await db.q(`SELECT * FROM refund_incidents WHERE (closed IS NOT TRUE OR closed IS NULL) ORDER BY opened_at DESC LIMIT 200`);
  res.json({ ok:true, items:q.rows });
});
r.post('/ledger/refund/incidents/ack', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { id, note }=req.body||{}; if(!id) return res.status(400).json({ ok:false, code:'ID_REQUIRED' });
  await db.q(`UPDATE refund_incidents SET acked=TRUE, acked_by=$2, acked_at=now(), note=COALESCE($3,note) WHERE id=$1`,[id, req.admin?.sub||'admin', note||null]);
  res.json({ ok:true });
});
module.exports=r;

