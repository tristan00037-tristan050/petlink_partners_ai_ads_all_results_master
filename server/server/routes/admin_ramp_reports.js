const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const { perfDaily, rollbackSummary }=require('../lib/ramp_analytics');
let alertsCh=null; try{ alertsCh=require('../lib/alerts_channels'); }catch(_){ alertsCh=null; }
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/reports/pilot/ramp/perf.json', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const days=parseInt(String(req.query.days||'14'),10);
  const aid = req.query.advertiser_id? parseInt(String(req.query.advertiser_id),10) : null;
  res.json(await perfDaily(days, aid));
});

r.get('/reports/pilot/ramp/rollback.json', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const days=parseInt(String(req.query.days||'30'),10);
  res.json(await rollbackSummary(days));
});

r.get('/reports/pilot/ramp/perf', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const j=await perfDaily(parseInt(String(req.query.days||'14'),10), null);
  const rows=(j.items||[]).map(x=>`<tr><td>${x.day}</td><td>${x.total}</td><td>${(x.live_share*100).toFixed(1)}%</td><td>${(x.fail_rate*100).toFixed(1)}%</td><td>${x.live_amount}</td></tr>`).join('');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Ramp Performance</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2 style="margin:0 0 8px">Ramp Performance (최근 ${j.days}일)</h2>
    <table border="1" cellspacing="0" cellpadding="6">
      <thead><tr><th>Day</th><th>Total</th><th>Live%</th><th>Fail%</th><th>Live Amount</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`);
});

r.get('/reports/pilot/ramp/perf.csv', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const j=await perfDaily(parseInt(String(req.query.days||'14'),10), null);
  const lines=['day,total,live_ok,sim_ok,sbx_ok,fails,live_share,fail_rate,live_amount,nonlive_amount']
    .concat((j.items||[]).map(x=>[x.day,x.total,x.live_ok,x.sim_ok,x.sbx_ok,x.fails,(x.live_share).toFixed(4),(x.fail_rate).toFixed(4),x.live_amount,x.nonlive_amount].join(',')));
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.end(lines.join('\n'));
});

r.post('/reports/pilot/ramp/autopush/run', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  const perf=await perfDaily(7,null);
  const rb  =await rollbackSummary(7);
  const payload={ kind:'RAMP_REPORT', perf:perf.items||[], rollback:rb.items||[], ts:new Date().toISOString() };
  let sent=false; if(alertsCh){ const out=await alertsCh.notifyWithSeverity('info','RAMP_REPORT',payload); sent=!!out.ok; }
  res.json({ ok:true, sent, size:{ perf:(perf.items||[]).length, rollback:(rb.items||[]).length } });
});

module.exports=r;

