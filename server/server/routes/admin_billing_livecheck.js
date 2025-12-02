const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const pick=require('../lib/billing/factory'); const r=express.Router();
r.get('/live/checklist', admin.requireAdmin, async (req,res)=>{
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING==='false' && process.env.ENABLE_ADS_BILLING==='true';
  const readyJson = await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/ads/billing/ready', { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  let dlqRate = 0; try{
    const dlq = +(await db.q(`SELECT count(*) FROM outbox_dlq WHERE created_at>=now()-interval '7 days'`)).rows[0].count||0;
    const ob  = +(await db.q(`SELECT count(*) FROM outbox      WHERE created_at>=now()-interval '7 days'`)).rows[0].count||0;
    dlqRate = ob? dlq/ob : 0;
  }catch{}
  res.json({ ok:true, checklist: {
    ready: !!readyJson.ready,
    scope_locked: scopeLocked,
    dlq_rate_7d: dlqRate,
    slo: { success_rate_goal: 0.99, dlq_rate_goal: 0.005 }
  }});
});
module.exports=r;
