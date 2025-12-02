const db=require('../lib/db');
const fetchFn=(global.fetch||require('node-fetch'));
const base='http://localhost:'+ (process.env.PORT||'5902');
const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };

function dt(s){ return new Date(s).toISOString().slice(0,19).replace('T',' '); }
function pct(x){ return (x==null)?null:Math.round(x*10000)/100; }

async function pull(path){
  try{ const r=await fetchFn(base+path, H); if(!r.ok) return null; return await r.json(); }
  catch(_){ return null; }
}

function range(){
  const now = new Date();
  const end = process.env.PILOT_END ? new Date(process.env.PILOT_END) : now;
  const start = process.env.PILOT_START ? new Date(process.env.PILOT_START)
               : new Date(end.getTime() - ((parseInt(process.env.PILOT_WINDOW_DAYS||'30',10)||30)*24*60*60*1000));
  return { start, end };
}

async function q1(sql,args){ const r=await db.q(sql,args); return r.rows[0]||{}; }

async function computeCore(start, end){
  // 1) 결제 지표
  const pay=await q1(`
    WITH b AS (
      SELECT status, amount FROM ad_payments
      WHERE created_at BETWEEN $1 AND $2
    )
    SELECT
      COUNT(*)::int total,
      SUM((status='CAPTURED')::int)::int ok,
      SUM((status='FAILED')::int)::int fail,
      COALESCE(SUM(CASE WHEN status='CAPTURED' THEN amount ELSE 0 END),0)::bigint captured_amount
    FROM b
  `,[start, end]);
  const pay_total=+pay.total||0, pay_ok=+pay.ok||0, pay_fail=+pay.fail||0;
  const pay_success_rate = pay_total? pay_ok/pay_total : 1;

  // 2) 웹앱 자동 승인율/5분 이내 비율
  const wa=await q1(`
    WITH b AS (
      SELECT COALESCE((flags->>'final')::text,'') AS final,
             EXTRACT(EPOCH FROM (approved_at - created_at)) AS lead
      FROM ad_creatives
      WHERE created_at BETWEEN $1 AND $2
    )
    SELECT
      COUNT(*)::int total,
      SUM(CASE WHEN final='approved' THEN 1 ELSE 0 END)::int AS approved,
      SUM(CASE WHEN final='approved' AND lead IS NOT NULL AND lead<=300 THEN 1 ELSE 0 END)::int AS under5
    FROM b
  `,[start, end]);
  const wa_total=+wa.total||0, wa_approved=+wa.approved||0, wa_under5=+wa.under5||0;
  const auto_rate    = wa_total? wa_approved/wa_total : 1;
  const under5_rate  = wa_total? wa_under5/wa_total   : 1;

  // 3) 세션 게이트 스냅샷(24h)
  const sessGate = await pull('/admin/metrics/session/gate');

  // 4) 종합 게이트 스냅샷
  const card = await pull('/admin/reports/pilot-card.json');

  // 5) 규모(온보딩/구독)
  const adv = await q1(`SELECT COUNT(*)::int AS advertisers FROM advertiser_profile`,[]);
  const subs = await q1(`SELECT COUNT(*)::int AS active FROM ad_subscriptions WHERE status IN ('ACTIVE','TRIAL')`,[]);

  return {
    period: { start, end },
    payments: { total:pay_total, ok:pay_ok, fail:pay_fail, success_rate:pay_success_rate, captured_amount:+pay.captured_amount||0 },
    webapp: { total:wa_total, approved:wa_approved, auto_rate, under5_rate },
    session: { pass: !!(sessGate?.gate?.pass), rate: sessGate?.gate?.rate ?? null, p95_ms: sessGate?.gate?.p95_ms ?? null },
    gates: {
      webapp:  { pass: !!(card?.gates?.webapp?.pass),  auto_rate: card?.gates?.webapp?.auto_rate ?? auto_rate, under5m_rate: card?.gates?.webapp?.under5m_rate ?? under5_rate },
      billing: { pass: !!(card?.gates?.billing?.pass) },
      admin:   { pass: !!(card?.gates?.admin?.pass) },
      session: { pass: !!(card?.gates?.session?.pass), rate: sessGate?.gate?.rate ?? null, p95_ms: sessGate?.gate?.p95_ms ?? null }
    },
    scale: { advertisers:+adv.advertisers||0, active_subscriptions:+subs.active||0 }
  };
}

function recommendations(core){
  const out=[];
  if(core.webapp.auto_rate<0.85)  out.push({sev:'critical', area:'WebApp', msg:'자동 승인율 개선: AUTOFIX 규칙/금칙어 튜닝 및 생성 UI 힌트 강화'});
  if(core.webapp.under5_rate<0.95) out.push({sev:'warn', area:'WebApp', msg:'5분 내 완료율 개선: 검증/수정 워커 간격 최적화'});
  if(core.payments.success_rate<0.99) out.push({sev:'critical', area:'Billing', msg:'결제 성공률 제고: CHARGE 실패코드 상위 3종 재시도/가이드'});
  if((core.session.p95_ms??0)>1500) out.push({sev:'warn', area:'Session', msg:'세션 p95 지연 단축: 자동 갱신 주기/네트워크 경로 점검'});
  if((core.session.rate??1)<0.95) out.push({sev:'critical', area:'Session', msg:'Refresh 성공률 개선: 토큰 회전/유휴 타임아웃 재검토'});
  if(out.length===0) out.push({sev:'info', area:'All', msg:'주요 임계 모두 충족. 배포 대비 운영가이드 정리'});
  return out;
}

function toMarkdown(core, rc){
  const s=core.period;
  const lines=[
    `# Pilot Final Report`,
    ``,
    `기간: **${dt(s.start)} ~ ${dt(s.end)}**`,
    ``,
    `## 1) 핵심 지표`,
    `- 결제 성공률: **${pct(core.payments.success_rate)}%** (성공 ${core.payments.ok}/${core.payments.total}), 매출(샌드박스): ${core.payments.captured_amount}`,
    `- 자동 승인율: **${pct(core.webapp.auto_rate)}%**, 5분 내 완료율: **${pct(core.webapp.under5_rate)}%**`,
    `- 세션: pass=${core.session.pass}, refresh 성공률=${core.session.rate??'—'}, p95=${core.session.p95_ms??'—'}ms`,
    `- 규모: 온보딩 매장=${core.scale.advertisers}, 구독=${core.scale.active_subscriptions}`,
    ``,
    `## 2) 게이트`,
    `- WebApp=${core.gates.webapp.pass}, Billing=${core.gates.billing.pass}, Admin=${core.gates.admin.pass}, Session=${core.gates.session.pass}`,
    ``,
    `## 3) 개선 권고`,
    ...rc.map(x=>`- [${x.sev}] ${x.area}: ${x.msg}`),
    ``,
    `— r10.0`
  ];
  return lines.join('\n');
}

async function build(){
  const { start, end }=range();
  const core=await computeCore(start, end);
  const rc=recommendations(core);
  const md=toMarkdown(core, rc);
  const title=`Pilot Final Report (${dt(start)} ~ ${dt(end)})`;
  return { ok:true, title, summary_md: md, payload: { core, recommendations: rc } };
}

module.exports={ build };

