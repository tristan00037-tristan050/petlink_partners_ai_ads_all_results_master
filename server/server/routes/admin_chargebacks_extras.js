const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db'); const cbk=require('../lib/cbk_ops');
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

// 기간 영향 조회
r.get('/ledger/cbk/period-impact', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period= String(req.query.period||'').trim(); if(!period) return res.status(400).json({ ok:false, code:'PERIOD_REQUIRED' });
  return res.json(await cbk.computeImpact(period));
});
// 기간 영향 + 태깅 업서트
r.post('/ledger/cbk/period-impact/run', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const period= String((req.body?.period||req.query?.period||'')).trim(); if(!period) return res.status(400).json({ ok:false, code:'PERIOD_REQUIRED' });
  return res.json(await cbk.upsertImpactAndTags(period));
});
// 증빙 매니페스트(JSON)
r.get('/ledger/cbk/evidence/manifest', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id= parseInt(String(req.query.id||'0'),10); if(!id) return res.status(400).json({ ok:false, code:'ID_REQUIRED' });
  return res.json(await cbk.evidenceManifest(id));
});
// SLA 상태/워처
r.get('/ledger/cbk/sla/status', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=> res.json(await cbk.listSlaOpen()));
r.post('/ledger/cbk/sla/watch/run', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const thrDays= parseInt(String(req.query?.thr_days||req.body?.thr_days||'7'),10);
  return res.json(await cbk.slaScan(thrDays));
});
r.post('/ledger/cbk/incidents/ack', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { id }= req.body||{}; if(!id) return res.status(400).json({ ok:false, code:'ID_REQUIRED' });
  return res.json(await cbk.ackIncident(parseInt(String(id),10), req.admin?.sub||'admin'));
});
// CSV(기간)
r.get('/ledger/cbk/export.csv', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const per= String(req.query.period||'').trim(); if(!per) return res.status(400).end('period required');
  const [y,m]=per.split('-').map(n=>parseInt(n,10));
  const from=new Date(Date.UTC(y,m-1,1,0,0,0)); const to=new Date(Date.UTC(m===12?y+1:y, m===12?1:m, 1,0,0,0));
  const rows=(await db.q(`
    SELECT c.id AS case_id, c.txid, c.advertiser_id, c.amount, c.outcome, c.closed_at
      FROM chargeback_cases c
     WHERE c.closed_at >= $1 AND c.closed_at < $2
     ORDER BY c.closed_at ASC`, [from,to])).rows;
  const esc=(s)=> String(s??'').replace(/"/g,'""');
  const csv = ['case_id,txid,advertiser_id,amount,outcome,closed_at,tag']
              .concat(rows.map(r=>[r.case_id,r.txid,r.advertiser_id,r.amount,r.outcome,r.closed_at?.toISOString?.()||r.closed_at,'CBK'].map(esc).map(x=>`"${x}"`).join(',')))
              .join('\n');
  res.setHeader('Content-Type','text/csv; charset=utf-8'); res.end(csv);
});

module.exports=r;

