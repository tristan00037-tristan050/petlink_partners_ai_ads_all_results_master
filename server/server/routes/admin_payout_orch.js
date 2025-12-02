const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db');
const orch=require('../lib/payouts_orch');
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const H=adminCORS||((req,res,next)=>next());

r.get('/ledger/payouts/run/preview', H, guard, async (req,res)=>{
  const period=String(req.query.period||'').trim() || new Date().toISOString().slice(0,7);
  res.json(await orch.preview(period));
});

r.post('/ledger/payouts/run/build', H, guard, express.json(), async (req,res)=>{
  const period=String(req.body?.period||'').trim() || new Date().toISOString().slice(0,7);
  const commit= !!(req.body?.commit===true);
  const actor = String(req.body?.actor||req.admin?.sub||'admin');
  res.json(await orch.build(period,{ commit, actor, note:req.body?.note||null }));
});

r.post('/ledger/payouts/run/approve', H, guard, express.json(), async (req,res)=>{
  const id=Number(req.body?.batch_id||0);
  if(!id) return res.status(400).json({ ok:false, code:'BATCH_ID_REQUIRED' });
  const approver = String(req.body?.approver||req.admin?.sub||'admin2');
  res.json(await orch.approve(id,{ approver }));
});

r.post('/ledger/payouts/run/send', H, guard, express.json(), async (req,res)=>{
  const id=Number(req.body?.batch_id||0);
  if(!id) return res.status(400).json({ ok:false, code:'BATCH_ID_REQUIRED' });
  const url=process.env.PAYOUT_WEBHOOK_URL||null;
  res.json(await orch.send(id,{ webhookUrl:url }));
});

r.get('/ledger/payouts/run/batches', H, guard, async (_req,res)=>{
  const q=await db.q(`SELECT id,period,status,total_amount,item_count,dryrun,created_by,approved_by,created_at
                        FROM payout_batches
                       ORDER BY id DESC LIMIT 200`);
  res.json({ ok:true, items:q.rows });
});

r.get('/ledger/payouts/run/batch/:id/export.csv', H, guard, async (req,res)=>{
  const csv=await orch.exportCsv(Number(req.params.id));
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.setHeader('Content-Disposition','attachment; filename="payout_batch_'+req.params.id+'.csv"');
  res.end(csv);
});

module.exports=r;

