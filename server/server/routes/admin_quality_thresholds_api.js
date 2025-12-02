const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const r=express.Router();
r.get('/quality/thresholds', admin.requireAdmin, async (req,res)=>{
  const q=await db.q(`SELECT channel, min_approval, max_rejection, updated_at FROM quality_thresholds ORDER BY channel`);
  res.json({ ok:true, items:q.rows });
});
r.post('/quality/thresholds', admin.requireAdmin, express.json(), async (req,res)=>{
  const items=Array.isArray(req.body?.items)?req.body.items:[];
  if(!items.length) return res.status(400).json({ ok:false, code:'EMPTY' });
  for(const it of items){
    await db.q(`INSERT INTO quality_thresholds(channel,min_approval,max_rejection,updated_at)
                 VALUES($1,$2,$3,now())
                 ON CONFLICT (channel) DO UPDATE SET min_approval=EXCLUDED.min_approval, max_rejection=EXCLUDED.max_rejection, updated_at=now()`,
                 [String(it.channel).toUpperCase(), Number(it.min_approval), Number(it.max_rejection)]);
  }
  res.json({ ok:true, upserted: items.length });
});
module.exports=r;
