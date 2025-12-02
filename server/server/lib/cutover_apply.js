const db=require('../lib/db');

async function ensurePolicyRow(advertiser_id){
  await db.q(`INSERT INTO subscription_live_policy(advertiser_id,percent_live,enabled,updated_at)
            VALUES($1,0,FALSE,now())
            ON CONFLICT(advertiser_id) DO NOTHING`, [advertiser_id]);
}
async function getPercent(advertiser_id){
  const q=await db.q(`SELECT percent_live FROM subscription_live_policy WHERE advertiser_id=$1`,[advertiser_id]);
  return q.rows[0]?.percent_live ?? 0;
}
async function applyCutover({advertiser_id, target_percent, actor, reason='cutover', dryrun=true}){
  const before=await getPercent(advertiser_id);
  const after = Math.max(0, Math.min(100, parseInt(target_percent,10)||0));
  if(!dryrun){
    await ensurePolicyRow(advertiser_id);
    await db.q(`UPDATE subscription_live_policy
                SET percent_live=$2, enabled=TRUE, ramp_enabled=FALSE, updated_at=now()
                WHERE advertiser_id=$1`, [advertiser_id, after]);
  }
  await db.q(`INSERT INTO cutover_actions(kind,advertiser_id,before_percent,after_percent,reason,actor,source)
              VALUES('CUTOVER',$1,$2,$3,$4,$5,'manual')`,
              [advertiser_id,before,after,reason||'cutover',actor||'admin']);
  return { ok:true, before, after, dryrun };
}
async function applyBackout({advertiser_id, fallback_percent=0, actor, reason='backout', dryrun=true, source='manual'}){
  const before=await getPercent(advertiser_id);
  const after = Math.max(0, Math.min(100, parseInt(fallback_percent,10)||0));
  if(!dryrun){
    await ensurePolicyRow(advertiser_id);
    await db.q(`UPDATE subscription_live_policy
                SET percent_live=$2, enabled=TRUE, ramp_enabled=FALSE, updated_at=now()
                WHERE advertiser_id=$1`, [advertiser_id, after]);
  }
  await db.q(`INSERT INTO cutover_actions(kind,advertiser_id,before_percent,after_percent,reason,actor,source)
              VALUES('BACKOUT',$1,$2,$3,$4,$5,$6)`,
              [advertiser_id,before,after,reason||'backout',actor||'admin',source]);
  return { ok:true, before, after, dryrun };
}
module.exports={ applyCutover, applyBackout };

