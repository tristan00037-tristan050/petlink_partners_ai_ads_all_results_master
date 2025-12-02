const express=require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db');
const { ingestFromSources, requestRefund, approveRefund, execRefund, runRecon, buildEvidenceBundle }=require('../lib/ledger');

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.post('/ledger/ingest/run', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const days= parseInt(String(req.body?.days||7),10);
  res.json(await ingestFromSources(days));
});

r.post('/ledger/refund/request', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { ledger_txid, advertiser_id, amount, reason } = req.body||{};
  const out=await requestRefund({ ledger_txid, advertiser_id, amount, reason, actor: req.admin?.sub||'admin' });
  res.json(out);
});
r.post('/ledger/refund/approve', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { id, reject=false }=req.body||{};
  res.json(await approveRefund({ id, approver:req.admin?.sub||'approver', reject }));
});
r.post('/ledger/refund/exec', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { id }=req.body||{};
  res.json(await execRefund({ id }));
});

r.post('/ledger/recon/run', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const days= parseInt(String(req.body?.days||7),10);
  res.json(await runRecon(days));
});

r.get('/ledger/export.csv', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  const q=await db.q(`SELECT txid,advertiser_id,env,kind,parent_txid,amount,currency,status,external_id,event_at
                      FROM live_ledger ORDER BY event_at DESC LIMIT 20000`);
  const head='txid,advertiser_id,env,kind,parent_txid,amount,currency,status,external_id,event_at';
  const body=(q.rows||[]).map(r=>[
    r.txid,r.advertiser_id,r.env,r.kind,(r.parent_txid||''),r.amount,r.currency,r.status,(r.external_id||''),(r.event_at?.toISOString?.()||r.event_at)
  ].join(',')).join('\n');
  res.setHeader('Content-Type','text/csv; charset=utf-8'); res.end(head+'\n'+body);
});

r.get('/ledger/evidence/build', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const txid = String(req.query.txid||'');
  if(!txid) return res.status(400).json({ ok:false, code:'TXID_REQUIRED' });
  const out=await buildEvidenceBundle({ ledger_txid: txid });
  if(!out.ok) return res.status(500).json(out);
  res.json({ ok:true, sha256: out.sha256, path: out.path });
});

module.exports=r;

