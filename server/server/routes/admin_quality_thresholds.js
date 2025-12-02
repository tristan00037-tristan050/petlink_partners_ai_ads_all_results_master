const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const alerts=require('../lib/alerts'); const r=express.Router();
r.get('/quality/thresholds', admin.requireAdmin, async (req,res)=>{
  const q = await db.q(`SELECT channel, min_approval, max_rejection, updated_at FROM quality_thresholds ORDER BY channel`);
  res.json({ ok:true, items:q.rows });
});
r.post('/quality/thresholds', admin.requireAdmin, express.json(), async (req,res)=>{
  const items = Array.isArray(req.body?.items)? req.body.items: [];
  for(const it of items){
    await db.q(`INSERT INTO quality_thresholds(channel,min_approval,max_rejection,updated_at)
                VALUES($1,$2,$3,now())
                ON CONFLICT(channel) DO UPDATE SET min_approval=EXCLUDED.min_approval, max_rejection=EXCLUDED.max_rejection, updated_at=now()`,
                [String(it.channel||''), Number(it.min_approval||0.9), Number(it.max_rejection||0.08)]);
  }
  res.json({ ok:true, upserted: items.length });
});
r.post('/quality/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const days = Math.max(1, Math.min(90, parseInt(req.body?.days||'7',10)));
  const ths = await db.q(`SELECT channel, min_approval, max_rejection FROM quality_thresholds`);
  const m = await db.q(`
    WITH base AS (
      SELECT channel,
             CASE WHEN (flags->>'final')='approved' THEN 1 ELSE 0 END AS approved,
             CASE WHEN (flags->>'final')='rejected' THEN 1 ELSE 0 END AS rejected
      FROM ad_creatives WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT channel,
           CASE WHEN COUNT(*)=0 THEN 1.0 ELSE AVG(approved)::float END AS approval_rate,
           CASE WHEN COUNT(*)=0 THEN 0.0 ELSE AVG(rejected)::float END AS rejection_rate
    FROM base GROUP BY channel`,[days]);
  const byCh = new Map(m.rows.map(x=>[x.channel, x]));
  let breaches=[];
  for(const t of ths.rows){
    const cur = byCh.get(t.channel)||{approval_rate:1.0,rejection_rate:0.0};
    if (Number(cur.approval_rate)<Number(t.min_approval) || Number(cur.rejection_rate)>Number(t.max_rejection)){
      breaches.push({ channel:t.channel, approval_rate:cur.approval_rate, rejection_rate:cur.rejection_rate,
                      min_approval: t.min_approval, max_rejection: t.max_rejection });
    }
  }
  if (breaches.length) await alerts.notify('QUALITY_THRESHOLD_BREACH', { days, breaches });
  res.json({ ok:true, breaches });
});
module.exports=r;
