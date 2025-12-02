const fetchFn = (global.fetch || require('node-fetch'));
const cache = (function(){ try { return require('../lib/cache_2layer'); } catch(_) { return null; } })();
const port = (process.env.PORT||'5902');
const base = 'http://localhost:'+port;
const AK = process.env.ADMIN_KEY||'';

function now(){ return new Date(); }
function ymd(d){ return d.toISOString().slice(0,10); }
function ym(d){ return d.toISOString().slice(0,7); }

async function call(path, body){
  const r = await fetchFn(base+path, { method:'POST', headers:{'X-Admin-Key':AK,'Content-Type':'application/json'}, body: JSON.stringify(body||{}) });
  try { return await r.json(); } catch(_){ return {ok:false}; }
}

async function getCache(k){ try{ return cache? (await cache.get(k)) : null; }catch(_){ return null; } }
async function setCache(k,v){ try{ return cache? (await cache.set(k,v,0)) : null; }catch(_){ return null; } }

async function tick(){
  const d = now();
  const hh = d.getHours(), mm = d.getMinutes();
  const dow = (d.getDay()===0)? 7 : d.getDay(); // 1..7 (월..일)
  const dom = d.getDate();

  // Weekly: 월간 단위 중복 방지 — 날짜 비교
  const W_DOW = parseInt(process.env.PILOT_WEEKLY_DOW||'1',10);
  const W_HH  = parseInt(process.env.PILOT_WEEKLY_HH||'9',10);
  const W_MIN = parseInt(process.env.PILOT_WEEKLY_MIN||'30',10);
  const wkKey = 'pilot_sched_weekly_last';
  if (dow===W_DOW && hh===W_HH && mm===W_MIN){
    const last = (await getCache(wkKey))?.date;
    if (last !== ymd(d)){
      const ok = (await call('/admin/reports/pilot/autopush/run-weekly',{__sched:true}))?.ok;
      await setCache(wkKey, { date: ymd(d), ok: !!ok, ts: new Date().toISOString() });
      console.log('[pilot-scheduler] weekly run', {ok});
    }
  }

  // Monthly: 월 단위 중복 방지 — 년월 비교
  const M_DOM = parseInt(process.env.PILOT_MONTHLY_DOM||'1',10);
  const M_HH  = parseInt(process.env.PILOT_MONTHLY_HH||'9',10);
  const M_MIN = parseInt(process.env.PILOT_MONTHLY_MIN||'45',10);
  const moKey = 'pilot_sched_monthly_last';
  if (dom===M_DOM && hh===M_HH && mm===M_MIN){
    const last = (await getCache(moKey))?.ym;
    if (last !== ym(d)){
      const ok = (await call('/admin/reports/pilot/autopush/run-monthly',{__sched:true}))?.ok;
      await setCache(moKey, { ym: ym(d), ok: !!ok, ts: new Date().toISOString() });
      console.log('[pilot-scheduler] monthly run', {ok});
    }
  }
}

// 60초 주기 체크
setInterval(()=>tick().catch(()=>{}), 60*1000);
setTimeout(()=>tick().catch(()=>{}), 1500);

// 상태 조회용 헬퍼
async function status(){
  const wk = (await getCache('pilot_sched_weekly_last')) || null;
  const mo = (await getCache('pilot_sched_monthly_last')) || null;
  return {
    ok:true,
    weekly: { dow:+(process.env.PILOT_WEEKLY_DOW||'1'), hh:+(process.env.PILOT_WEEKLY_HH||'9'), min:+(process.env.PILOT_WEEKLY_MIN||'30'), last:wk },
    monthly:{ dom:+(process.env.PILOT_MONTHLY_DOM||'1'), hh:+(process.env.PILOT_MONTHLY_HH||'9'), min:+(process.env.PILOT_MONTHLY_MIN||'45'), last:mo }
  };
}
module.exports = { status };

