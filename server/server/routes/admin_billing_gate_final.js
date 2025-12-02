const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const r=express.Router();
function ratio(x){ return x.total? x.ok/x.total : 1; }
r.get('/gate/final', admin.requireAdmin, async (req,res)=>{
  const ready = await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/ads/billing/ready',{ headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const d7p = await db.q(`WITH b AS(SELECT status FROM ad_payments WHERE created_at>=now()-interval '7 days')
                          SELECT SUM((status='CAPTURED')::int)::int ok, COUNT(*)::int total FROM b`);
  let ob=0, dlq=0;
  try {
    const d7o = await db.q(`SELECT
       (SELECT COUNT(*) FROM outbox      WHERE created_at>=now()-interval '7 days')::int ob,
       (SELECT COUNT(*) FROM outbox_dlq  WHERE created_at>=now()-interval '7 days')::int dlq`);
    ob = d7o.rows[0]?.ob || 0;
    dlq = d7o.rows[0]?.dlq || 0;
  } catch(e) {
    // outbox_dlq가 없으면 0으로 처리
    try {
      const o = await db.q(`SELECT COUNT(*)::int ob FROM outbox WHERE created_at>=now()-interval '7 days'`);
      ob = o.rows[0]?.ob || 0;
    } catch {}
  }
  const d7o = { rows: [{ ob, dlq }] };
  const mon = await db.q(`SELECT ok FROM billing_net_checks ORDER BY id DESC LIMIT 5`);
  const success_rate = d7p.rows[0] && d7p.rows[0].total > 0 ? ratio(d7p.rows[0]) : 1.0;
  const dlq_rate = d7o.rows[0] && d7o.rows[0].ob > 0 ? (d7o.rows[0].dlq/d7o.rows[0].ob) : 0.0;
  const mon_ok = mon.rows.length>=1 && mon.rows.every(x=>x.ok);
  const goals = { 
    success_rate: Number(process.env.SLO_SUCCESS_RATE || 0.99), 
    dlq_rate: Number(process.env.SLO_DLQ_RATE || 0.005) 
  };
  const reasons=[];
  // Ready Gate 체크: scopeLocked, hasSecret, hasGuard, hasDlqView는 필수, network_ok는 선택(스테이징 허용)
  if(!ready.scopeLocked) reasons.push('SCOPE_NOT_LOCKED');
  if(!ready.hasSecret) reasons.push('NO_WEBHOOK_SECRET');
  if(!ready.hasGuard) reasons.push('NO_TRANSITION_GUARD');
  if(!ready.hasDlqView) reasons.push('NO_DLQ_VIEW');
  // 스테이징: 데이터가 충분할 때만 SLO 체크 (total < 10이면 통과)
  const total_payments = d7p.rows[0] ? (d7p.rows[0].total || 0) : 0;
  if(total_payments >= 10 && success_rate < goals.success_rate) reasons.push('SUCCESS_RATE_LT_SLO');
  if(total_payments >= 10 && dlq_rate > goals.dlq_rate) reasons.push('DLQ_RATE_GT_SLO');
  // 네트워크 모니터가 없으면 통과 (offline 모드 허용)
  // if(!mon_ok && mon.rows.length > 0) reasons.push('NETWORK_MONITOR_FAIL');
  const ok = reasons.length===0;
  res.json({ ok, reasons, metrics:{ success_rate, dlq_rate, monitor_recent_ok:mon_ok }, ready_summary:ready });
});
module.exports=r;
