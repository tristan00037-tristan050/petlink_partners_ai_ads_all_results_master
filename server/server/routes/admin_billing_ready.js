const express=require('express');
const admin=require('../mw/admin');
const db=require('../lib/db');
const pick=require('../lib/billing/factory');
const r=express.Router();

r.get('/ready', admin.requireAdmin, async (req,res)=>{
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING==='false' && process.env.ENABLE_ADS_BILLING==='true';
  const hasSecret   = !!process.env.PAYMENT_WEBHOOK_SECRET;
  const adapterName = (process.env.BILLING_ADAPTER||'mock');
  const mode        = (process.env.BILLING_MODE||'sandbox');
  let network_ok=false;
  try{
    const adapter = pick()();
    const probe = adapter.__probeToken ? await adapter.__probeToken() : { offline:true, has_token:false };
    network_ok = !!probe.has_token;
  }catch{}
  // DB 트리거/뷰 존재 확인(관용적)
  let hasGuard=false, hasDlqView=true;
  try{
    const g = await db.q(`SELECT COUNT(*)::int c FROM pg_trigger WHERE tgname='ad_payments_guard_transition_tr'`); hasGuard=Number(g.rows[0].c||0)>0;
  }catch{}
  try{
    await db.q(`SELECT 1 FROM outbox_dlq LIMIT 1`);
  }catch{ hasDlqView=false; }

  const ready = scopeLocked && hasSecret && hasGuard && hasDlqView && network_ok;
  res.json({ ok:true, ready, scopeLocked, hasSecret, hasGuard, hasDlqView, network_ok, adapter:adapterName, mode });
});

module.exports=r;
