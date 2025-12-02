const express=require('express'); const db=require('../lib/db');
const router=express.Router();
router.post('/snapshot',async(req,res)=>{
  const {rows}=await db.q(`SELECT id,invoice_no,amount FROM ad_payments WHERE status='CAPTURED' AND id NOT IN(SELECT payment_id FROM ad_settlements WHERE payment_id IS NOT NULL)`);
  let total=0; for(const p of rows){
    const fee=Math.floor(p.amount*0.03); const net=p.amount-fee;
    await db.q(`INSERT INTO ad_settlements(payment_id,invoice_no,gross,fee,net,settled_at) VALUES($1,$2,$3,$4,$5,now())`,
      [p.id,p.invoice_no,p.amount,fee,net]);
    total+=net;
  }
  res.json({ok:true,processed:rows.length,total_net:total});
});
module.exports=router;
