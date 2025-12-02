const express=require('express'); const db=require('../lib/db'); const router=express.Router();

router.post('/', express.json(), async (req,res)=>{
  const { advertiser_id, pm_type, provider, token, brand, last4, set_default } = req.body||{};
  if(!advertiser_id || !pm_type || !provider || !token) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  await db.transaction(async(c)=>{
    await c.query(`INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default)
                   VALUES($1,$2,$3,$4,$5,$6,$7)
                   ON CONFLICT(advertiser_id,provider,token) DO NOTHING`,
                   [advertiser_id, pm_type, provider, token, brand||null, last4||null, !!set_default]);
    if(set_default){
      await c.query(`UPDATE payment_methods
                       SET is_default = (id = (SELECT id FROM payment_methods WHERE advertiser_id=$1 AND provider=$2 AND token=$3 LIMIT 1))
                     WHERE advertiser_id=$1`, [advertiser_id, provider, token]);
    }
  });
  res.json({ ok:true });
});

router.get('/', async (req,res)=>{
  const { advertiser_id } = req.query;
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_REQUIRED' });
  const { rows } = await db.q(`SELECT id,pm_type,provider,brand,last4,is_default,created_at FROM payment_methods WHERE advertiser_id=$1 ORDER BY id DESC`, [advertiser_id]);
  res.json({ ok:true, items: rows });
});

router.delete('/:id', async (req,res)=>{
  const id = parseInt(req.params.id,10);
  await db.q(`DELETE FROM payment_methods WHERE id=$1`, [id]);
  res.json({ ok:true });
});

router.post('/:id/default', async (req,res)=>{
  const id = parseInt(req.params.id,10);
  const { rows } = await db.q(`SELECT advertiser_id FROM payment_methods WHERE id=$1`, [id]);
  if(!rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  const adv = rows[0].advertiser_id;
  await db.transaction(async(c)=>{
    await c.query(`UPDATE payment_methods SET is_default=false WHERE advertiser_id=$1`, [adv]);
    await c.query(`UPDATE payment_methods SET is_default=true WHERE id=$1`, [id]);
  });
  res.json({ ok:true });
});

module.exports = router;
