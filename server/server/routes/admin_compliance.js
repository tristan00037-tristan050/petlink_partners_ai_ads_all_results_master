const express=require('express'); const db=require('../lib/db');
const router=express.Router();
router.post('/sanitize',async(req,res)=>{
  await db.q(`UPDATE ad_payments SET metadata=metadata-'card_number'-'email'-'phone' WHERE metadata?'card_number' OR metadata?'email' OR metadata?'phone'`);
  res.json({ok:true,message:'PII sanitized'});
});
module.exports=router;
