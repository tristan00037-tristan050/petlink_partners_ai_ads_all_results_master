const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const { computeWithCbk, applyCbkToSnapshot, toCsv, toMarkdown }=require('../lib/ledger_periods_cbk');

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/ledger/periods/preview2', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period=String(req.query.period||''); if(!period) return res.status(400).json({ ok:false, code:'PERIOD_REQUIRED' });
  res.json(await computeWithCbk(period));
});

r.post('/ledger/periods/close2', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  try{
    const period=String((req.body||{}).period||''); if(!period) return res.status(400).json({ ok:false, code:'PERIOD_REQUIRED' });
    const out=await applyCbkToSnapshot(period);
    res.json(out);
  }catch(e){
    console.error('[close2]',e);
    res.status(500).json({ ok:false, code:'INTERNAL_ERROR', message:e?.message });
  }
});

r.get('/ledger/periods/:period/export2.csv', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const v=await computeWithCbk(String(req.params.period));
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.end(toCsv(v.items||[]));
});

r.get('/ledger/periods/:period/report.md', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const v=await computeWithCbk(String(req.params.period));
  res.setHeader('Content-Type','text/markdown; charset=utf-8');
  res.end(toMarkdown(v));
});

module.exports=r;

