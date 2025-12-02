const express = require('express');
const admin = require('../mw/admin');
const r = express.Router();

r.get('/preflight', admin.requireAdmin, (req,res)=>{
  const adapter = (process.env.BILLING_ADAPTER||'mock').toLowerCase();
  const mode = (process.env.BILLING_MODE||'sandbox').toLowerCase();
  const hasKeys = !!(process.env.BOOTPAY_APP_ID && process.env.BOOTPAY_PRIVATE_KEY);
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING === 'false' && process.env.ENABLE_ADS_BILLING === 'true';
  const ready = (mode === 'sandbox') && scopeLocked;
  res.json({ ok:true, ready, adapter, mode, has_bootpay_keys: hasKeys, scope_locked: scopeLocked });
});
module.exports = r;
