const express=require('express'); const db=require('../lib/db'); const outbox=require('../lib/outbox');
const router=express.Router();

router.post('/refund', express.json(), async (req,res)=>{
  const {order_id, amount, reason, refund_id} = req.body||{};
  const amt = Number(amount);
  if(!order_id || !Number.isFinite(amt) || amt<=0) return res.status(400).json({ok:false, code:'INVALID_INPUT'});
  try{
    await db.transaction(async (c)=>{
      const p = await c.query(`SELECT id, amount, status, refunded_total FROM payments WHERE order_id=$1 FOR UPDATE`, [order_id]);
      if(!p.rows.length) throw Object.assign(new Error('PAYMENT_NOT_FOUND'), {status:404, code:'PAYMENT_NOT_FOUND'});
      const row = p.rows[0];
      if(row.status!=='CAPTURED') throw Object.assign(new Error('INVALID_STATE'), {status:409, code:'REFUND_NOT_ALLOWED_IN_STATE'});
      if(refund_id){
        const ex = await c.query(`SELECT amount,status FROM refunds WHERE refund_id=$1`, [refund_id]);
        if(ex.rows.length){
          if(ex.rows[0].amount===amt && ex.rows[0].status==='SUCCEEDED'){ return res.json({ok:true, order_id, refunded: amt}); }
          throw Object.assign(new Error('REPLAY_MISMATCH'), {status:409, code:'REFUND_REPLAY_MISMATCH'});
        }
      }
      const remaining = row.amount - row.refunded_total;
      if(amt > remaining) throw Object.assign(new Error('AMOUNT_EXCEEDS'), {status:409, code:'REFUND_EXCEEDS_REMAINING'});
      await c.query(`INSERT INTO refunds(refund_id,order_id,amount,reason,status) VALUES($1,$2,$3,$4,'SUCCEEDED')`,
                    [refund_id||null, order_id, amt, reason||null]);
      await c.query(`UPDATE payments SET refunded_total=refunded_total+$2,
                      status=CASE WHEN refunded_total+$2 >= amount THEN 'CANCELED' ELSE status END,
                      updated_at=now() WHERE order_id=$1`, [order_id, amt]);
      const pay = await c.query(`SELECT id,status,refunded_total FROM payments WHERE order_id=$1`,[order_id]);
      await outbox.addEventTx(c,'PAYMENT_REFUND_SUCCEEDED','payment', pay.rows[0].id, {order_id, amount:amt, reason});
      if(pay.rows[0].status==='CANCELED'){
        await outbox.addEventTx(c,'PAYMENT_CANCELED','payment', pay.rows[0].id, {order_id});
      }
    });
    return res.json({ok:true, order_id, refunded: amt});
  }catch(e){
    const sc = e.status || 500, code = e.code || 'REFUND_ERROR';
    return res.status(sc).json({ok:false, code});
  }
});

module.exports=router;
