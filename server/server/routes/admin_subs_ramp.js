const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db'); const fetchFn=(global.fetch||require('node-fetch'));
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };
const BASE='http://localhost:'+ (process.env.PORT||'5902');

function planArr(s){ return String(s||'').split(',').map(x=>parseInt(x.trim(),10)).filter(x=>!isNaN(x)&&x>=0&&x<=100); }
async function preflight(){ try{ const rs=await fetchFn(BASE+'/admin/prod/live/preflight', H); return rs.ok ? await rs.json() : null; }catch(_){ return null; } }
async function acksla(){ try{ const rs=await fetchFn(BASE+'/admin/reports/pilot/flip/acksla', H); return rs.ok ? await rs.json() : null; }catch(_){ return null; } }

r.get('/prod/live/subs/ramp/status', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id = parseInt(String(req.query.advertiser_id||'0'),10);
  const q  = await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id IN ($1,0) ORDER BY advertiser_id DESC LIMIT 1`,[id]);
  const p  = q.rows[0]||{};
  const plan= planArr(p.ramp_plan||'');
  let idx = Number(p.ramp_index||0);
  while(idx < plan.length && (p.percent_live||0) >= plan[idx]) idx++;
  const next = (idx < plan.length) ? plan[idx] : null;
  const pre  = await preflight(); const sla = await acksla();
  res.json({ ok:true, policy:p, next_percent: next, gate:{ preflight:pre?.pass??false, acksla:sla?.pass??false } });
});

r.post('/prod/live/subs/ramp/dryrun', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const id = parseInt(String(req.body?.advertiser_id||'0'),10);
  const q  = await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id IN ($1,0) ORDER BY advertiser_id DESC LIMIT 1`,[id]);
  const p  = q.rows[0]||{};
  const plan= planArr(p.ramp_plan||'');
  let idx = Number(p.ramp_index||0);
  while(idx < plan.length && (p.percent_live||0) >= plan[idx]) idx++;
  const next = (idx < plan.length) ? plan[idx] : null;
  const pre  = await preflight(); const sla = await acksla();
  res.json({ ok:true, advertiser_id:id, current:p.percent_live||0, next_percent: next, can_apply: !!(next!=null && pre?.pass && sla?.pass) });
});

r.post('/prod/live/subs/ramp/apply', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const id = parseInt(String(req.body?.advertiser_id||'0'),10);
  const force = !!req.body?.force;
  const q  = await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id=$1`,[id]);
  if(!q.rows.length) return res.status(404).json({ ok:false, code:'POLICY_NOT_FOUND' });
  const p  = q.rows[0];
  const plan= planArr(p.ramp_plan||'');
  let idx = Number(p.ramp_index||0);
  while(idx < plan.length && (p.percent_live||0) >= plan[idx]) idx++;
  if(idx >= plan.length) return res.json({ ok:true, done:true, percent_live:p.percent_live });
  const next = plan[idx];

  let allow=true;
  if(!force){
    const pre  = await preflight(); const sla = await acksla();
    allow = !!(pre?.pass && sla?.pass);
    if(!allow) return res.json({ ok:false, code:'GATE_BLOCK', preflight:pre?.pass??false, acksla:sla?.pass??false });
  }

  await db.q(`UPDATE subscription_live_policy
              SET percent_live=$1, ramp_index=$2, ramp_last_at=now(), updated_at=now()
              WHERE advertiser_id=$3`, [next, idx, id]);
  res.json({ ok:true, applied:true, to: next });
});

r.get('/reports/pilot/subs/daily', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  try{
    const j=await db.q(`SELECT created_at::date d, decided, outcome, COUNT(*)::int n
                        FROM subs_autoroute_journal
                        WHERE created_at >= now()-interval '30 days'
                        GROUP BY 1,2,3 ORDER BY 1 DESC,2,3`);
    res.json({ ok:true, items:j.rows });
  }catch(e){
    // 테이블이 없으면 빈 결과 반환
    res.json({ ok:true, items:[] });
  }
});

// 정책 조회/저장 (UI에서 사용)
r.get('/prod/live/subs/policy', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id = parseInt(String(req.query.advertiser_id||'0'),10);
  const q  = await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id=$1`,[id]);
  const p  = q.rows[0]||null;
  res.json({ ok:true, policy:p });
});

r.post('/prod/live/subs/policy', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id, enabled, percent_live, cap_amount_per_day, cap_attempts_per_day, ramp_enabled, ramp_plan, ramp_min_interval_minutes } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  
  const q = await db.q(`SELECT * FROM subscription_live_policy WHERE advertiser_id=$1`,[advertiser_id]);
  if(q.rows.length){
    await db.q(`UPDATE subscription_live_policy SET
                enabled=COALESCE($2,enabled),
                percent_live=COALESCE($3,percent_live),
                cap_amount_per_day=$4,
                cap_attempts_per_day=$5,
                ramp_enabled=COALESCE($6,ramp_enabled),
                ramp_plan=COALESCE($7,ramp_plan),
                ramp_min_interval_minutes=COALESCE($8,ramp_min_interval_minutes),
                updated_at=now()
                WHERE advertiser_id=$1`,
                [advertiser_id, enabled, percent_live, cap_amount_per_day, cap_attempts_per_day, ramp_enabled, ramp_plan, ramp_min_interval_minutes]);
  }else{
    await db.q(`INSERT INTO subscription_live_policy(advertiser_id,enabled,percent_live,cap_amount_per_day,cap_attempts_per_day,ramp_enabled,ramp_plan,ramp_min_interval_minutes)
                VALUES($1,$2,$3,$4,$5,$6,$7,$8)`,
                [advertiser_id, enabled??true, percent_live??0, cap_amount_per_day, cap_attempts_per_day, ramp_enabled??false, ramp_plan||'0,5,10,25,50', ramp_min_interval_minutes??1440]);
  }
  res.json({ ok:true });
});

module.exports=r;

