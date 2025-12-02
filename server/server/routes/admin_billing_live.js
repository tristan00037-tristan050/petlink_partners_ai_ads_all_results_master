const express=require('express');let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db'); const { decide }=require('../lib/rollout_gate');
const { captureLive }=require('../lib/billing_live_adapter');
const fetchFn=(global.fetch||require('node-fetch'));
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const base='http://localhost:'+ (process.env.PORT||'5902'); const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };
async function safe(path){ try{ const rs=await fetchFn(base+path,H); if(!rs.ok) return null; return await rs.json(); }catch(_){ return null; } }

async function loadLimits(){
  const q=await db.q(`SELECT * FROM live_billing_limits LIMIT 1`);
  const v=q.rows[0]||{ max_amount_per_tx:50000, max_amount_per_day:200000, max_attempts_per_day:10, dryrun:true };
  return { ...v };
}
async function todayAgg(){
  const q=await db.q(`SELECT COALESCE(SUM(amount),0)::int AS sum, COUNT(*)::int AS cnt
                      FROM live_billing_journal
                      WHERE created_at::date = now()::date AND result IN ('LIVE_OK','SIM_OK')`);
  return q.rows[0]||{ sum:0, cnt:0 };
}

r.get('/prod/live/limits', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  res.json({ ok:true, limits: await loadLimits(), today: await todayAgg() });
});

r.post('/prod/live/probe', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, amount } = req.body||{};
  if(!advertiser_id || !amount) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const limits=await loadLimits(); const agg=await todayAgg();
  const roll = await decide(Number(advertiser_id)).catch(()=>({ eligible_live:false, mode:'sbx' }));
  const guard = {
    per_tx_ok: amount <= limits.max_amount_per_tx,
    per_day_amount_ok: (agg.sum + amount) <= limits.max_amount_per_day,
    per_day_count_ok: (agg.cnt + 1) <= limits.max_attempts_per_day
  };
  res.json({ ok:true, dryrun: !!limits.dryrun, rollout: roll, guard, allowed: (roll.eligible_live && Object.values(guard).every(Boolean)) });
});

r.post('/prod/live/charge-exec', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, amount, note } = req.body||{};
  if(!advertiser_id || !amount) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const limits=await loadLimits(); const agg=await todayAgg();
  const roll = await decide(Number(advertiser_id)).catch(()=>({ eligible_live:false, mode:'sbx' }));
  const guard = {
    per_tx_ok: amount <= limits.max_amount_per_tx,
    per_day_amount_ok: (agg.sum + amount) <= limits.max_amount_per_day,
    per_day_count_ok: (agg.cnt + 1) <= limits.max_attempts_per_day
  };
  const allowed = roll.eligible_live && Object.values(guard).every(Boolean);
  let result = 'SIM_FAIL', message='not allowed or dryrun';
  // 드라이런 모드에서는 allowed가 false여도 시뮬레이션은 수행 (테스트 목적)
  if(limits.dryrun){
    if(allowed){
      result='SIM_OK'; message='dryrun success';
    }else{
      result='SIM_FAIL'; message='dryrun: not eligible or guard failed';
    }
  }else if(allowed){
    const live=await captureLive({ advertiser_id, amount, meta:{ note } });
    result = live.ok ? 'LIVE_OK' : 'LIVE_FAIL';
    message = live.ok ? (live.txid||'ok') : (live.message||'failed');
  }
  await db.q(`INSERT INTO live_billing_journal(advertiser_id,amount,mode,eligible_live,decided_mode,result,message)
              VALUES($1,$2,$3,$4,$5,$6,$7)`,
              [advertiser_id, amount, limits.dryrun?'dryrun':'live', !!roll.eligible_live, roll.mode, result, message]);
  res.json({ ok:true, dryrun: !!limits.dryrun, allowed, guard, rollout: roll, outcome:{ result, message } });
});

r.get('/prod/live/journal', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const q=await db.q(`SELECT * FROM live_billing_journal ORDER BY id DESC LIMIT 200`);
  res.json({ ok:true, items:q.rows });
});

// Rollout gate (r10.3 의존)
r.get('/prod/rollout/gate', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const advertiser_id = Number(req.query.advertiser_id) || 0;
  const roll = await decide(advertiser_id).catch(()=>({ eligible_live:false, mode:'sbx' }));
  res.json({ ok:true, advertiser_id, rollout: roll });
});

module.exports=r;

