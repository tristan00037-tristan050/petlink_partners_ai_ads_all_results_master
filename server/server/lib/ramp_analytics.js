const db=require('../lib/db');

async function perfDaily(days=14, advertiserId=null){
  try{
    const q=await db.q(`
      WITH j AS (
        SELECT (created_at AT TIME ZONE 'Asia/Seoul')::date d,
               advertiser_id, amount, outcome
        FROM subs_autoroute_journal
        WHERE created_at >= now() - ($1||' days')::interval
          AND ($2::bigint IS NULL OR advertiser_id=$2)
      )
      SELECT d,
             COUNT(*)::int AS total,
             SUM((outcome='LIVE_OK')::int)::int AS live_ok,
             SUM((outcome='SIM_OK')::int)::int  AS sim_ok,
             SUM((outcome='SBX_OK')::int)::int  AS sbx_ok,
             SUM((outcome LIKE '%FAIL%')::int)::int AS fails,
             COALESCE(SUM(amount) FILTER (WHERE outcome='LIVE_OK'),0)::int AS live_amount,
             COALESCE(SUM(amount) FILTER (WHERE outcome='SBX_OK' OR outcome='SIM_OK'),0)::int AS nonlive_amount
      FROM j GROUP BY d ORDER BY d;
    `,[days, advertiserId]);
    const rows=q.rows||[];
    const series=rows.map(r=>{
      const t=Number(r.total||0);
      const liveShare = t? (Number(r.live_ok||0)/t) : 0;
      const failRate  = t? (Number(r.fails||0)/t) : 0;
      return { day:r.d, total:t, live_ok:+r.live_ok, sim_ok:+r.sim_ok, sbx_ok:+r.sbx_ok, fails:+r.fails,
               live_share: liveShare, fail_rate: failRate, live_amount:+r.live_amount, nonlive_amount:+r.nonlive_amount };
    });
    return { ok:true, days, items:series };
  }catch(e){
    // 테이블이 없으면 빈 결과 반환
    return { ok:true, days, items:[] };
  }
}

async function rollbackSummary(days=30){
  try{
    const q=await db.q(`
      WITH e AS (
        SELECT (created_at AT TIME ZONE 'Asia/Seoul')::date d, reason_tags
        FROM ramp_backoff_events
        WHERE created_at >= now() - ($1||' days')::interval
      ),
      flat AS (
        SELECT d, unnest(reason_tags) AS tag FROM e
      )
      SELECT d, tag, COUNT(*)::int AS n
      FROM flat GROUP BY d, tag ORDER BY d, tag;
    `,[days]);
    return { ok:true, days, items:q.rows||[] };
  }catch(e){
    // 테이블이 없으면 빈 결과 반환
    return { ok:true, days, items:[] };
  }
}

module.exports={ perfDaily, rollbackSummary };

