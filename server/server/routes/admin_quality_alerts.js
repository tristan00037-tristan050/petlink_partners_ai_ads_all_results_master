const express=require('express'); const admin=require('../mw/admin'); const alerts=require('../lib/alerts'); const r=express.Router();
r.post('/quality/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const payload = { note:'quality alert wire check', now:new Date().toISOString() };
  const sent = (await alerts.notify('QUALITY_ALERT_WIRE', payload)).ok;
  res.json({ ok:true, sent });
});
module.exports=r;
