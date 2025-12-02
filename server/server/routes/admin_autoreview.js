const express=require('express');
const db=require('../lib/db');
const admin=require('../mw/admin');
const q=require('../lib/quality');
const r=express.Router();

r.post('/ads/autoreview/run', admin.requireAdmin, express.json(), async (req,res)=>{
  const limit = Math.max(1, Math.min(100, parseInt(req.body?.limit||'10',10)));
  const pending = await db.q(`
    SELECT * FROM ad_creatives
     WHERE approved_at IS NULL AND reviewed_at IS NULL
     ORDER BY created_at ASC
     LIMIT $1
  `,[limit]);

  let approved=0, rejected=0;
  for(const c of pending.rows){
    const flags = c.flags || {};
    const text = flags.text || '';
    const channel = c.channel || 'NAVER';
    const v = q.validate({ text, channel });
    if(v.autoApprove){
      await db.q(`UPDATE ad_creatives SET approved_at=now(), reviewed_at=now(), flags=jsonb_set(COALESCE(flags,'{}'::jsonb),'{final}','"approved"') WHERE id=$1`,[c.id]);
      approved++;
    }else{
      await db.q(`UPDATE ad_creatives SET reviewed_at=now(), flags=jsonb_set(COALESCE(flags,'{}'::jsonb),'{final}','"rejected"') WHERE id=$1`,[c.id]);
      rejected++;
    }
  }

  res.json({ ok:true, processed: pending.rows.length, approved, rejected });
});

module.exports=r;
