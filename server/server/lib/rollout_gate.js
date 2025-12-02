const db=require('./db');

// 간단한 rollout gate (코호트 기반)
async function decide(advertiser_id){
  // 방법 1: 환경변수 기반 (LIVE_BILLING_COHORT_IDS)
  const COHORT_IDS = (process.env.LIVE_BILLING_COHORT_IDS || '').split(',').filter(Boolean).map(Number);
  if(COHORT_IDS.includes(Number(advertiser_id))){
    return { eligible_live: true, mode: 'live' };
  }
  
  // 방법 2: subscription_live_policy 기반 (percent_live > 0이고 enabled=true)
  try{
    const q = await db.q(`SELECT percent_live, enabled FROM subscription_live_policy WHERE advertiser_id=$1`,[advertiser_id]);
    if(q.rows.length > 0){
      const p = q.rows[0];
      if(p.enabled && (p.percent_live || 0) > 0){
        return { eligible_live: true, mode: 'live', percent_live: p.percent_live };
      }
    }
  }catch(_){}
  
  // 기본: 모든 광고주는 sbx
  return { eligible_live: false, mode: 'sbx' };
}
module.exports = { decide };

