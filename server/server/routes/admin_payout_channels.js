const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const { upsertChannel, listChannels, buildBankFile, ensureTransfersFromBatch, sendByChannel, applyReceiptSimulate, listDispatchLog }=require('../lib/payout_channels');
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.post('/ledger/payouts/channels/upsert', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const ch=await upsertChannel(req.body||{});
  res.json({ ok:true, item: ch });
});
r.get('/ledger/payouts/channels', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  res.json({ ok:true, items: await listChannels() });
});
r.post('/ledger/payouts/batch/build-bankfile', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const batchId = parseInt(String(req.body?.batch_id||'0'),10);
  const format  = String(req.body?.format||'CSV');
  if(!batchId) return res.status(400).json({ ok:false, code:'BATCH_ID_REQUIRED' });
  const out = await buildBankFile(batchId, format);
  await ensureTransfersFromBatch(batchId, out.id);
  res.json({ ok:true, ...out });
});
r.post('/ledger/payouts/batch/send2', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const batchId = parseInt(String(req.body?.batch_id||'0'),10);
  const bankId  = parseInt(String(req.body?.bank_file_id||'0'),10);
  const chId    = parseInt(String(req.body?.channel_id||'0'),10);
  if(!batchId || !bankId || !chId) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  res.json(await sendByChannel({ batchId, bankFileId: bankId, channelId: chId }));
});
r.post('/ledger/payouts/batch/receipts/simulate', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const batchId = parseInt(String(req.body?.batch_id||'0'),10);
  const status  = String(req.body?.status||'CONFIRMED');
  if(!batchId) return res.status(400).json({ ok:false, code:'BATCH_ID_REQUIRED' });
  res.json(await applyReceiptSimulate(batchId, status));
});
r.get('/ledger/payouts/batch/dispatch/log', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const batchId = parseInt(String(req.query?.batch_id||'0'),10);
  if(!batchId) return res.status(400).json({ ok:false, code:'BATCH_ID_REQUIRED' });
  res.json({ ok:true, items: await listDispatchLog(batchId) });
});

module.exports=r;

