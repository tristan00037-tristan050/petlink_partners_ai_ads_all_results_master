const fetchFn=(global.fetch||require('node-fetch'));

async function safe(path){
  try{ const r=await fetchFn('http://localhost:'+ (process.env.PORT||'5902') + path,{headers:{'X-Admin-Key':process.env.ADMIN_KEY||''}}); if(!r.ok) return null; return await r.json(); }
  catch(_){ return null; }
}
function tagSummary(tags){ if(!tags||!tags.length) return 'unknown'; return tags.join(','); }

async function compute(){ // 최신 상태 스냅샷 기반
  const card  = await safe('/admin/reports/pilot-card.json');
  const daily = await safe('/admin/reports/daily.json');
  const sess  = await safe('/admin/metrics/session/gate');
  const tags=[];
  const T={AUTO_MIN:0.85, UNDER5_MIN:0.95, ADMIN_OK:0.95, SESS_OK:0.95, SESS_P95:1500};
  if(card && card.gates){
    const g=card.gates;
    if(g.webapp && g.webapp.pass===false) tags.push('WEBAPP_GATE_FAIL');
    if(g.billing && g.billing.pass===false) tags.push('BILLING_GATE_FAIL');
    if(g.admin   && g.admin.pass===false)   tags.push('ADMIN_MIN_FAIL');
    if(g.session && g.session.pass===false) tags.push('SESSION_GATE_FAIL');
    if(g.webapp && (g.webapp.auto_rate??1)<T.AUTO_MIN) tags.push('AUTO_RATE_LOW');
    if(g.webapp && (g.webapp.under5m_rate??1)<T.UNDER5_MIN) tags.push('UNDER5_RATE_LOW');
  }
  if(daily?.metrics?.d1){
    if((daily.metrics.d1.success_rate??1)<T.ADMIN_OK) tags.push('PAY_SUCCESS_RATE_LOW');
    if((daily.metrics.d1.dlq_rate??0)>0.01) tags.push('DLQ_RATE_HIGH');
  }
  if(sess?.gate){
    if((sess.gate.rate??1)<T.SESS_OK) tags.push('SESSION_REFRESH_LOW');
    if((sess.gate.p95_ms??0)>T.SESS_P95) tags.push('SESSION_P95_HIGH');
  }
  const unique=[...new Set(tags)];
  return { tags: unique, summary: tagSummary(unique), snapshot:{ card, daily: daily?.metrics?.d1, session: sess?.gate } };
}

module.exports={ compute };

