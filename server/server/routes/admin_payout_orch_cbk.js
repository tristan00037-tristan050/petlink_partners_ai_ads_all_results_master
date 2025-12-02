const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const { previewWithCbk }=require('../lib/payouts_cbk');

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/ledger/payouts/run/preview2', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period=String(req.query.period||''); if(!period) return res.status(400).json({ ok:false, code:'PERIOD_REQUIRED' });
  res.json(await previewWithCbk(period));
});

module.exports=r;

