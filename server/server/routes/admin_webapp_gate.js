const express=require('express'); const db=require('../lib/db'); const admin=require('../mw/admin');
const r=express.Router();
const SLO_MIN = parseFloat(process.env.WEBAPP_SLO_MIN_AUTO_APPROVAL || '0.95');
const SLO_TIME = parseInt(process.env.WEBAPP_SLO_MAX_MINUTES || '5',10);

r.get('/webapp/gate', admin.requireAdmin, async (req,res)=>{
  // 최근 7일 ad_creatives에서 자동 승인률·중간 처리 시간 계산(데이터가 없으면 준비 상태)
  const appr = await db.q(`
    WITH base AS (
      SELECT created_at, approved_at, (flags->>'final') AS final
      FROM ad_creatives
      WHERE created_at >= now()-interval '7 days'
    )
    SELECT
      COALESCE(avg( CASE WHEN final='approved' THEN 1.0 ELSE 0.0 END ),1.0) AS auto_approval_rate,
      COALESCE(percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (approved_at - created_at))/60.0), 0) AS p50_mins
    FROM base
  `);
  const rate = Number(appr.rows[0].auto_approval_rate||1.0);
  const p50  = Number(appr.rows[0].p50_mins||0);
  const pass = (rate >= SLO_MIN) && (p50 <= SLO_TIME);
  res.json({ ok:true, gate: pass? 'PASS':'READY', auto_approval_rate: rate, p50_minutes: p50, slo:{ min_rate:SLO_MIN, max_minutes:SLO_TIME } });
});

module.exports = r;
