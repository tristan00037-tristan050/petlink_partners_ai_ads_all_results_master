const express = require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const { computePeriod, closePeriod, getStatus } = require('../lib/ledger_periods');

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/ledger/periods/status', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  res.json(await getStatus());
});

r.post('/ledger/periods/preview', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const period = String(req.body?.period||'').trim();
  if(!/^\d{4}-\d{2}$/.test(period)) return res.status(400).json({ ok:false, code:'INVALID_PERIOD' });
  res.json(await computePeriod(period));
});

r.post('/ledger/periods/close', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const period = String(req.body?.period||'').trim();
  const dryrun = !(req.body?.commit===true);
  if(!/^\d{4}-\d{2}$/.test(period)) return res.status(400).json({ ok:false, code:'INVALID_PERIOD' });
  const out = await closePeriod(period, (req.admin?.sub||'admin'), dryrun);
  res.json(out);
});

// Payout 미리보기: 스냅샷(있으면) 또는 즉시 계산 결과 반환
r.get('/ledger/periods/:period/payouts/preview', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period = String(req.params.period||'').trim();
  if(!/^\d{4}-\d{2}$/.test(period)) return res.status(400).json({ ok:false, code:'INVALID_PERIOD' });
  const comp = await computePeriod(period);
  // 순지표(net) 기준 정렬
  comp.items.sort((a,b)=> (b.net||0) - (a.net||0));
  res.json({ ok:true, period, items: comp.items, totals: comp.totals });
});

// CSV Export (미리보기 결과 CSV)
r.get('/ledger/periods/:period/export.csv', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period = String(req.params.period||'').trim();
  if(!/^\d{4}-\d{2}$/.test(period)) return res.status(400).json({ ok:false, code:'INVALID_PERIOD' });
  const comp = await computePeriod(period);
  const header = 'period,advertiser_id,charges,refunds,net,entries';
  const lines = comp.items.map(r=>[period,r.advertiser_id,r.charges,r.refunds,r.net,r.entries].join(','));
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.end([header, ...lines].join('\n'));
});

module.exports = r;

