const express = require('express');
const admin = require('../mw/admin');
const getAdapter = require('../lib/billing/factory');
const r = express.Router();

r.get('/preflight/network', admin.requireAdmin, async (req,res)=>{
  try{
    const adapter = getAdapter();
    const probe = adapter.__probeToken ? await adapter.__probeToken() : { offline:true, has_token:false };
    res.json({ ok:true, mode:(process.env.BILLING_MODE||'sandbox'),
               adapter:(process.env.BILLING_ADAPTER||'mock'), ...probe });
  }catch(e){
    res.json({ ok:false, error:String(e?.message||e) });
  }
});

module.exports = r;
