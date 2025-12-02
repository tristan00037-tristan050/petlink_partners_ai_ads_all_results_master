const express=require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db');
const { applyCutover }=require('../lib/cutover_apply');
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

// Rollout Assign: 코호트 할당 (p5 = 5%, p10 = 10%, etc.)
r.post('/prod/rollout/assign', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, env, cohort } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  
  // cohort에서 percent 추출 (p5 -> 5, p10 -> 10, etc.)
  let percent = 0;
  if(cohort && cohort.startsWith('p')){
    percent = parseInt(cohort.slice(1), 10) || 0;
  } else if(cohort){
    percent = parseInt(cohort, 10) || 0;
  }
  
  // env가 'live'이고 percent > 0이면 cutover 적용
  if(env === 'live' && percent > 0){
    const out = await applyCutover({ 
      advertiser_id: Number(advertiser_id), 
      target_percent: percent, 
      actor: (req.admin?.sub||'admin'), 
      reason: `cohort-assign-${cohort}`, 
      dryrun: false 
    });
    return res.json({ ok:out.ok, advertiser_id, cohort, percent, cutover: out });
  }
  
  // 기본: subscription_live_policy 업데이트만
  const q = await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id=$1`,[advertiser_id]);
  if(q.rows.length){
    await db.q(`UPDATE subscription_live_policy SET percent_live=$1, enabled=TRUE, updated_at=now() WHERE advertiser_id=$2`,
                [percent, advertiser_id]);
  }else{
    await db.q(`INSERT INTO subscription_live_policy(advertiser_id,percent_live,enabled,updated_at) VALUES($1,$2,TRUE,now())`,
                [advertiser_id, percent]);
  }
  
  res.json({ ok:true, advertiser_id, cohort, percent, env });
});

module.exports=r;

