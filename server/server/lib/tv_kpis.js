const db=require('../lib/db');

async function rampRecent(minutes=15, advertiser_id=null){
  const P=[minutes]; let w='';
  if(advertiser_id){ P.push(advertiser_id); w=`AND advertiser_id = $${P.length}`; }
  const q=await db.q(`
    SELECT
      COUNT(*)::int AS total,
      SUM((decided IN ('live','sim'))::int)::int AS live_total,
      SUM((outcome IN ('LIVE_FAIL','SIM_FAIL'))::int)::int AS fail_total,
      SUM(CASE WHEN decided IN ('live','sim') THEN amount ELSE 0 END)::int AS live_amount,
      SUM(CASE WHEN decided='sbx' THEN amount ELSE 0 END)::int AS nonlive_amount
    FROM subs_autoroute_journal
    WHERE created_at >= now() - ($1||' minutes')::interval
      ${w}`, P);
  const r=q.rows[0]||{total:0,live_total:0,fail_total:0,live_amount:0,nonlive_amount:0};
  const live_share = r.total>0 ? (r.live_total/r.total) : 0;
  const fail_rate  = r.live_total>0 ? (r.fail_total/r.live_total) : 0;
  return { ok:true, window_min: minutes, ...r, live_share, fail_rate };
}
module.exports={ rampRecent };

