const express=require('express');
const db=require('../lib/db');
const r=express.Router();

r.get('/profile', async (req,res)=>{
  const id = parseInt(req.query.advertiser_id||'0',10);
  if(!id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  const q = await db.q(`SELECT * FROM advertiser_profile WHERE advertiser_id=$1`, [id]);
  res.json({ ok:true, profile: q.rows[0]||null });
});

r.put('/profile', express.json(), async (req,res)=>{
  const { advertiser_id, name, phone, email, address, meta } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  await db.q(`
    INSERT INTO advertiser_profile(advertiser_id,name,phone,email,address,meta,updated_at)
    VALUES($1,$2,$3,$4,$5,COALESCE($6,'{}'::jsonb),now())
    ON CONFLICT(advertiser_id) DO UPDATE
      SET name=EXCLUDED.name, phone=EXCLUDED.phone, email=EXCLUDED.email,
          address=EXCLUDED.address, meta=EXCLUDED.meta, updated_at=now()
  `,[advertiser_id, name||null, phone||null, email||null, address||null, meta?JSON.stringify(meta):null]);
  res.json({ ok:true });
});

module.exports=r;
