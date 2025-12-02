const express=require('express');const db=require('../lib/db');const admin=require('../mw/admin');const alerts=require('../lib/alerts');const r=express.Router();

async function metrics(days=1){
  const pay=await db.q(`WITH b AS(SELECT status,created_at FROM ad_payments WHERE created_at>=now()-($1||' days')::interval)
                        SELECT SUM((status='CAPTURED')::int)::int ok,
                               SUM((status='FAILED')::int)::int fail,
                               COUNT(*)::int total FROM b`,[days]);
  const ok=+pay.rows[0].ok||0, fail=+pay.rows[0].fail||0, total=+pay.rows[0].total||0;
  let dlq=0, ob=0; 
  try{dlq=+(await db.q(`SELECT count(*) FROM outbox_dlq WHERE created_at>=now()-($1||' days')::interval`,[days])).rows[0].count||0;}catch{}
  try{ob=+(await db.q(`SELECT count(*) FROM outbox WHERE created_at>=now()-($1||' days')::interval`,[days])).rows[0].count||0;}catch{}
  return { success_rate: total? ok/total:1, fail_rate: total? fail/total:0, dlq_rate: ob? dlq/ob:0, ok, fail, total };
}

r.get('/daily.json', admin.requireAdmin, async (req,res)=>{ 
  const d1=await metrics(1), d7=await metrics(7);
  res.json({ ok:true, metrics: { d1, d7 }, SLO: { success_rate:0.99, dlq_rate:0.005 } }); 
});

r.get('/daily', admin.requireAdmin, async (req,res)=>{
  const h={'X-Admin-Key':process.env.ADMIN_KEY||''};
  const j=await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/reports/daily.json',{headers:h})).json();
  const pct=x=> (Math.round(x*10000)/100)+'%';
  const c=(l,v,sub)=>`<div style="border:1px solid #ddd;border-radius:6px;padding:12px;min-width:230px"><div style="font-size:12px;color:#666">${l}</div><div style="font-size:22px;font-weight:700">${v}</div><div style="font-size:12px;color:#999">${sub}</div></div>`;
  const d1=j.metrics.d1,d7=j.metrics.d7,S=j.SLO;
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Daily Report</title>
  <div style="font:14px system-ui,Arial;padding:16px;display:flex;gap:12px;flex-wrap:wrap">
    ${c('결제 성공률(1d)', pct(d1.success_rate), 'SLO≥'+pct(S.success_rate)+' / 7d '+pct(d7.success_rate))}
    ${c('결제 실패율(1d)', pct(d1.fail_rate), '7d '+pct(d7.fail_rate))}
    ${c('DLQ 이동률(1d)',  pct(d1.dlq_rate),  'SLO<'+pct(S.dlq_rate)+' / 7d '+pct(d7.dlq_rate))}
  </div>`);
});

r.post('/dlq/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const th = Number(req.body?.threshold ?? process.env.ADMIN_ALERT_DLQ_RATE ?? 0.10);
  const d1 = (await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/reports/daily.json',{headers:{'X-Admin-Key':process.env.ADMIN_KEY||''}})).json()).metrics.d1;
  const sent = d1.dlq_rate > th ? (await alerts.notify('DLQ_THRESHOLD', { d1, th })).ok : false;
  res.json({ ok:true, sent, threshold: th, dlq_rate: d1.dlq_rate });
});

module.exports=r;
