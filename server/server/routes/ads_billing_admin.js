const express=require('express'); const db=require('../lib/db'); const admin=require('../mw/admin'); const router=express.Router();

router.use(admin.requireAdmin);

router.post('/deposits/import', express.json(), async (req,res)=>{
  const items = Array.isArray(req.body) ? req.body : [];
  let n=0;
  await db.transaction(async(c)=>{
    for(const it of items){
      await c.query(`INSERT INTO bank_deposits(advertiser_id,invoice_no,amount,deposit_time,bank_code,account_mask,ref_no,memo,created_by)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [it.advertiser_id||null, it.invoice_no||null, Number(it.amount||0), it.deposit_time||new Date().toISOString(),
         it.bank_code||null, it.account_mask||null, it.ref_no||null, it.memo||null, it.created_by||'admin']);
      n++;
      if(it.invoice_no && it.amount!=null){
        await c.query(`UPDATE ad_invoices SET status='PAID', updated_at=now() WHERE invoice_no=$1 AND amount=$2`, [it.invoice_no, Number(it.amount||0)]);
      }
    }
  });
  res.json({ ok:true, imported: n });
});

router.get('/deposits', async (req,res)=>{
  const { advertiser_id, invoice_no, from, to } = req.query;
  const params=[]; const where=[];
  if(advertiser_id){ params.push(Number(advertiser_id)); where.push(`advertiser_id=$${params.length}`); }
  if(invoice_no){ params.push(String(invoice_no)); where.push(`invoice_no=$${params.length}`); }
  if(from){ params.push(String(from)); where.push(`deposit_time>=to_timestamp($${params.length})`); }
  if(to){ params.push(String(to)); where.push(`deposit_time<=to_timestamp($${params.length})`); }
  const sql = `SELECT id,advertiser_id,invoice_no,amount,deposit_time,bank_code,ref_no,memo,created_by
               FROM bank_deposits ${where.length?'WHERE '+where.join(' AND '):''} ORDER BY id DESC LIMIT 200`;
  const { rows } = await db.q(sql, params);
  res.json({ ok:true, items: rows });
});

module.exports = router;
