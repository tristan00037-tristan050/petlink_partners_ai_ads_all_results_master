const fetchFn = (global.fetch || require('node-fetch'));
const db = require('../lib/db');
const VERSION = 'r9.6';

async function safeFetch(path){
  try{
    const r = await fetchFn('http://localhost:'+ (process.env.PORT||'5902') + path, { headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} });
    if(!r.ok) return null;
    return await r.json();
  }catch(_){ return null; }
}
function pct(v){ return (v==null)? null : Math.round(v*10000)/100; }

async function computeWindow(days){
  // Billing
  let pay;
  try{
    pay = await db.q(`
      WITH b AS (SELECT status FROM ad_payments WHERE created_at>=now()-($1||' days')::interval)
      SELECT SUM((status='CAPTURED')::int)::int ok, SUM((status='FAILED')::int)::int fail, COUNT(*)::int total FROM b
    `,[days]);
  }catch(_){ pay = {rows:[{ok:0,fail:0,total:0}]}; }
  const row = pay.rows[0]||{ok:0,fail:0,total:0};
  const ok = +row.ok||0, fail=+row.fail||0, total=+row.total||0;
  const billing_success = total? ok/total:1, billing_fail = total? fail/total:0;

  // WebApp(자동승인/5분이내)
  let ac;
  try{
    ac = await db.q(`
      WITH b AS (
        SELECT COALESCE((flags->>'final')::text,'') AS final,
               EXTRACT(EPOCH FROM (approved_at - created_at)) AS lead
        FROM ad_creatives WHERE created_at>=now()-($1||' days')::interval
      )
      SELECT
        SUM(CASE WHEN final='approved' THEN 1 ELSE 0 END)::int AS approved,
        SUM(CASE WHEN final='approved' AND lead IS NOT NULL AND lead<=300 THEN 1 ELSE 0 END)::int AS under5,
        COUNT(*)::int AS total
    `,[days]);
  }catch(_){ ac = {rows:[{approved:0,under5:0,total:0}]}; }
  const a = ac.rows[0]||{approved:0,under5:0,total:0};
  const auto_rate = a.total? (+a.approved)/a.total:1;
  const under5m_rate = a.total? (+a.under5)/a.total:1;

  // Session p95 (ms 컬럼 사용)
  let session_p95 = null;
  try{
    const s = await db.q(`SELECT percentile_disc(0.95) WITHIN GROUP (ORDER BY ms) p95
                          FROM session_events WHERE created_at>=now()-($1||' days')::interval
                            AND kind IN ('refresh_ok','refresh_fail')
                            AND ms IS NOT NULL`,[days]);
    session_p95 = Math.round(Number(s.rows[0]?.p95||0)) || null;
  }catch(_){
    try{
      const sum = await safeFetch(`/admin/metrics/session/summary?days=${days}`);
      session_p95 = sum?.app?.latency?.p95 ? Math.round(Number(sum.app.latency.p95)) : null;
    }catch(_){}
  }

  return { days, billing_success, billing_fail, auto_rate, under5m_rate, session_p95 };
}

function subject(period, go){
  const d = new Date().toISOString().slice(0,10);
  return `[Pilot ${period} | ${VERSION}] ${d} — ${go?'GO':'HOLD'}`;
}

function toMarkdown(period, m, go){
  return [
    `# Pilot ${period} Report — ${go?'GO ✅':'HOLD ⚠️'}  <${VERSION}>`,
    ``,
    `- Billing 성공률: **${pct(m.billing_success)}%**, 실패율: ${pct(m.billing_fail)}%`,
    `- 자동 승인율: **${pct(m.auto_rate)}%**, 5분 이내 완료율: ${pct(m.under5m_rate)}%`,
    `- Session p95: ${m.session_p95==null?'—':(m.session_p95+'ms')}`,
    ``,
    `> 기준: WebApp 자동 승인 ≥85%, 5분 이내 ≥95%, Billing 성공률 높을수록 우수, Session p95 < 1500ms`,
  ].join('\n');
}

async function build(period){ // 'weekly' | 'monthly'
  const days = (period==='monthly')? 30 : 7;
  const m = await computeWindow(days);
  const card = await safeFetch('/admin/reports/pilot-card.json');
  const overallGo = card?.overall?.go ?? ( (m.auto_rate>=0.85) && (m.under5m_rate>=0.95) );
  return {
    ok:true, version: VERSION, period,
    metrics: { billing_success:m.billing_success, billing_fail:m.billing_fail, auto_rate:m.auto_rate, under5m_rate:m.under5m_rate, session_p95:m.session_p95 },
    subject: subject(period, overallGo),
    markdown: toMarkdown(period, m, overallGo),
    overall: { go: overallGo }
  };
}

module.exports = { build, VERSION };

