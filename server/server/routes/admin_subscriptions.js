const express=require('express');
const db=require('../lib/db');
const admin=require('../mw/admin');

const r=express.Router();

function yyyymmdd(d=new Date()){
  const z = n=>String(n).padStart(2,'0');
  return d.getFullYear()+z(d.getMonth()+1)+z(d.getDate());
}

/** 구독 생성/수정 */
r.post('/ads/subscriptions', admin.requireAdmin, express.json(), async (req,res)=>{
  const { advertiser_id, plan_code, amount, bill_day, method_id } = req.body||{};
  if(!advertiser_id || !plan_code || !amount || !bill_day) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  await db.q(`
    INSERT INTO ad_subscriptions(advertiser_id,plan_code,amount,currency,method_id,bill_day,status,next_charge_at)
    VALUES($1,$2,$3,'KRW',$4,$5,'ACTIVE', date_trunc('day', now()))
    ON CONFLICT DO NOTHING
  `,[advertiser_id, plan_code, amount, method_id||null, bill_day]);
  res.json({ ok:true });
});

/** 월간 과금 워커 실행 */
r.post('/ads/subscriptions/run-billing', admin.requireAdmin, express.json(), async (req,res)=>{
  const today = parseInt(req.body?.today||new Date().getDate(),10);
  const limit = Math.max(1, Math.min(200, parseInt(req.body?.limit||'50',10)));

  const subs = await db.q(`
    SELECT * FROM ad_subscriptions
     WHERE status='ACTIVE'
       AND (
             bill_day=$1
             OR (next_attempt_at IS NOT NULL AND next_attempt_at <= now())
           )
     ORDER BY id ASC
     LIMIT $2
  `,[today, limit]);

  let ok=0, fail=0;
  for(const s of subs.rows){
    const inv = `SUB-${s.id}-${yyyymmdd()}`;
    // 인보이스 업서트
    await db.q(`
      INSERT INTO ad_invoices(invoice_no,advertiser_id,amount,currency,status,meta,updated_at,created_at)
      VALUES($1,$2,$3,'KRW','DUE',jsonb_build_object('subscription_id',$4),now(),now())
      ON CONFLICT (invoice_no) DO NOTHING
    `,[inv, s.advertiser_id, s.amount, s.id]);

    // 기본 수단 보장(없으면 조회)
    if(!s.method_id){
      const pm = await db.q(`SELECT id FROM payment_methods WHERE advertiser_id=$1 AND is_default=TRUE LIMIT 1`,[s.advertiser_id]);
      if(pm.rows.length){
        await db.q(`UPDATE ad_subscriptions SET method_id=$2 WHERE id=$1`,[s.id, pm.rows[0].id]);
      }
    }

    // CHARGE 호출 (샌드박스는 즉시 CAPTURED)
    try{
      const resp = await fetch(`http://localhost:${process.env.PORT||'5902'}/ads/billing/charge`,{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ invoice_no:inv, advertiser_id:s.advertiser_id, amount:s.amount })
      });
      const j = await resp.json().catch(()=>({}));
      const success = resp.ok && j?.status==='CAPTURED';
      if(success){
        ok++;
        // 영수증 번호 부여 + 다음 과금일
        const rcp = `RCP-${inv}`;
        await db.q(`UPDATE ad_invoices SET receipt_no=$2, status='PAID', updated_at=now() WHERE invoice_no=$1`,[inv, rcp]);
        await db.q(`UPDATE ad_subscriptions
                      SET retry_count=0, last_attempt_at=now(),
                          next_attempt_at=NULL,
                          next_charge_at = (date_trunc('month', now()) + interval '1 month') + ($1||' days')::interval
                    WHERE id=$2`,[Math.max(0,s.bill_day-1), s.id]);
      }else{
        fail++;
        const rc = (s.retry_count||0)+1;
        let next = "3 days"; if(rc>=2) next = "7 days";
        await db.q(`UPDATE ad_subscriptions
                      SET retry_count=$2, last_attempt_at=now(),
                          next_attempt_at = now() + interval '${next}',
                          status = CASE WHEN $2>=3 THEN 'PAUSED' ELSE status END
                    WHERE id=$1`,[s.id, rc]);
      }
    }catch(e){
      fail++;
    }
  }

  res.json({ ok:true, processed: subs.rows.length, success: ok, failed: fail });
});

module.exports=r;
