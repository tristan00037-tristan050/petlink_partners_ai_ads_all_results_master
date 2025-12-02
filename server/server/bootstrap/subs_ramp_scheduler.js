const db=require('../lib/db');
const fetchFn=(global.fetch||require('node-fetch'));
const TICK = (parseInt(process.env.SUBS_RAMP_TICK_SEC||'60',10)||60)*1000;
const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };
const BASE='http://localhost:'+ (process.env.PORT||'5902');

async function safeJson(path){
  try{ const r=await fetchFn(BASE+path,H); if(!r.ok) return null; return await r.json(); }catch(_){ return null; }
}
function parsePlan(s){ return String(s||'').split(',').map(x=>parseInt(x.trim(),10)).filter(x=>!isNaN(x)&&x>=0&&x<=100); }

async function loop(){
  try{
    const pol = await db.q(`SELECT * FROM subscription_live_policy WHERE ramp_enabled IS TRUE AND enabled IS TRUE`);
    if(!pol.rows.length) return;

    const pre = await safeJson('/admin/prod/live/preflight'); // r10.1
    const sla = await safeJson('/admin/reports/pilot/flip/acksla'); // r9.9
    const guardPass = !!(pre?.pass) && !!(sla?.pass);

    for(const p of pol.rows){
      const plan = parsePlan(p.ramp_plan); if(!plan.length) continue;
      const now  = Date.now();
      const last = p.ramp_last_at ? new Date(p.ramp_last_at).getTime() : 0;
      const due  = (now - last) >= ( (p.ramp_min_interval_minutes||1440) * 60 * 1000 );
      // 다음 단계 계산
      let idx = Number(p.ramp_index||0);
      // 현재 percent_live가 플랜보다 뒤처져 있으면 맞춰줌
      while(idx < plan.length && (p.percent_live||0) >= plan[idx]) idx++;
      if(idx >= plan.length) continue; // 종료

      const nextPct = plan[idx];
      if(!due || !guardPass) continue;

      await db.q(`UPDATE subscription_live_policy
                  SET percent_live=$1, ramp_index=$2, ramp_last_at=now(), updated_at=now()
                  WHERE advertiser_id=$3`,
                  [nextPct, idx, p.advertiser_id]);
      console.log('[subs_ramp] step', { adv:p.advertiser_id, to: nextPct, idx });
    }
  }catch(e){ console.warn('[subs_ramp] error', e&&e.message); }
}

setInterval(()=>loop().catch(()=>{}), TICK);
console.log('[subs_ramp] scheduler started', { tick_sec: TICK/1000 });
module.exports={};

