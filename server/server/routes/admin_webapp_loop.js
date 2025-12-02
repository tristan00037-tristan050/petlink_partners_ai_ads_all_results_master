const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const { execSync }=require('child_process'); const r=express.Router();

// GET /admin/webapp/loop/stats.json  (1d/7d: first_pass_ok, autofix_ok, rejected, rates)
r.get('/loop/stats.json', admin.requireAdmin, async (req,res)=>{
  async function win(days){
    const base = await db.q(`
      WITH base AS (
        SELECT loop_id, decision, used_autofix, created_at
        FROM ad_moderation_logs
        WHERE created_at >= now()-($1||' days')::interval
      ),
      ok1 AS ( SELECT count(*)::int c FROM base WHERE decision='APPROVED' AND used_autofix=false ),
      loops AS (
        SELECT COALESCE(loop_id, '_noid_') lid,
               max( (decision='APPROVED')::int ) as any_ok,
               max( (used_autofix=true)::int )  as any_fix
        FROM base GROUP BY COALESCE(loop_id, '_noid_')
      ),
      ok2 AS ( SELECT count(*)::int c FROM loops WHERE any_ok=1 AND any_fix=1 ),
      rej AS ( SELECT count(*)::int c FROM base WHERE decision='REJECT' ),
      tot AS ( SELECT count(*)::int c FROM base )
      SELECT (SELECT c FROM ok1) first_pass_ok,
             (SELECT c FROM ok2) autofix_ok,
             (SELECT c FROM rej) rejected,
             (SELECT c FROM tot) total
    `,[days]);
    const row = base.rows[0]||{first_pass_ok:0,autofix_ok:0,rejected:0,total:0};
    const total = Number(row.total||0);
    const first = Number(row.first_pass_ok||0), fix = Number(row.autofix_ok||0), rej = Number(row.rejected||0);
    const appr = total? (first+fix)/total : 1;
    return { first_pass_ok:first, autofix_ok:fix, rejected:rej, total, auto_approval_rate:appr };
  }
  const d1 = await win(1), d7 = await win(7);
  res.json({ ok:true, d1, d7, slo:{ min_auto_approval: Number(process.env.WEBAPP_GATE_APPROVE_RATE||0.95), max_p95_ms: Number(process.env.WEBAPP_GATE_P95_MS||300000) } });
});

// GET /admin/webapp/gate/report  : 게이트 종합 리포트(JSON)
r.get('/gate/report', admin.requireAdmin, async (req,res)=>{
  // p95는 기존 /admin/webapp/gate 에서 계산되므로 재활용
  const g = await (await fetch(`http://localhost:${process.env.PORT||'5902'}/admin/webapp/gate`, { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const s = await (await fetch(`http://localhost:${process.env.PORT||'5902'}/admin/webapp/loop/stats.json`, { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  res.json({ ok:true, gate:g, loop:s });
});

// POST /admin/webapp/evidence/export  : 증빙 번들 생성
r.post('/evidence/export', admin.requireAdmin, async (req,res)=>{
  try{
    const out = execSync('bash scripts/generate_webapp_evidence.sh', { encoding:'utf8' }).trim();
    res.json({ ok:true, file: out });
  }catch(e){ res.status(500).json({ ok:false, code:'EVIDENCE_FAIL', err: String(e.message||e) }); }
});

module.exports=r;
