const express=require("express"); const db=require("../lib/db");
const admin = require("../mw/admin_gate")||require("../mw/admin");
const r=express.Router();
const requireAdminAny = (admin.requireAdminAny || admin.requireAdmin);

// p50/p90/p95 계산 유틸
async function latency(db, surface, days){
  const q = await db.q(`
    SELECT
      percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) AS p50,
      percentile_cont(0.9) WITHIN GROUP (ORDER BY ms) AS p90,
      percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) AS p95
    FROM session_events
    WHERE surface=$1 AND kind='refresh_ok' AND ms IS NOT NULL
      AND created_at >= now() - ($2||' days')::interval
  `,[surface, days]);
  return { p50: Number(q.rows[0]?.p50||0), p90: Number(q.rows[0]?.p90||0), p95: Number(q.rows[0]?.p95||0) };
}

r.get("/metrics/session/summary", requireAdminAny, async (req,res)=>{
  const days = Math.max(1, Math.min(30, parseInt(req.query.days||"1",10)));
  const base = await db.q(`
    WITH ev AS (
      SELECT surface, kind, count(*)::int AS cnt
      FROM session_events
      WHERE created_at >= now() - ($1||' days')::interval
      GROUP BY surface, kind
    )
    SELECT surface,
      COALESCE(SUM(CASE WHEN kind='refresh_ok' THEN cnt END),0) AS refresh_ok,
      COALESCE(SUM(CASE WHEN kind='refresh_fail' THEN cnt END),0) AS refresh_fail,
      COALESCE(SUM(CASE WHEN kind='forced_logout' THEN cnt END),0) AS forced_logout,
      COALESCE(SUM(CASE WHEN kind='idle_logout' THEN cnt END),0) AS idle_logout
    FROM ev GROUP BY surface
  `,[days]);
  const app = base.rows.find(r=>r.surface==="app")||{refresh_ok:0,refresh_fail:0,forced_logout:0,idle_logout:0};
  const adminS = base.rows.find(r=>r.surface==="admin")||{refresh_ok:0,refresh_fail:0,forced_logout:0,idle_logout:0};
  const appLat = await latency(db,"app",days);
  const admLat = await latency(db,"admin",days);
  res.json({ ok:true, days, app: {counts:app, latency:appLat}, admin: {counts:adminS, latency:admLat} });
});

r.get("/metrics/session/dashboard", requireAdminAny, async (req,res)=>{
  const { fetch } = require("undici") || globalThis.fetch;
  const h = await (await fetch("http://localhost:"+ (process.env.PORT||"5902") +"/admin/metrics/session/summary",{
    headers:{"X-Admin-Key":process.env.ADMIN_KEY||""}
  })).json();
  const pct=(a,b)=> b? ((Math.round((a/b)*10000))/100)+"%":"0%";
  const app=h.app||{}, adm=h.admin||{};
  res.setHeader("Content-Type","text/html; charset=utf-8");
  res.end(`<!doctype html><meta charset="utf-8"><title>Session Metrics</title>
  <div style="font:14px system-ui,Arial;padding:16px;display:flex;gap:12px;flex-wrap:wrap">
    <div style="border:1px solid #ddd;border-radius:8px;padding:12px;min-width:260px">
      <h3 style="margin:0 0 8px">App (최근 ${h.days}일)</h3>
      <div>Refresh 성공률: <b>${pct(app.counts?.refresh_ok||0,(app.counts?.refresh_ok||0)+(app.counts?.refresh_fail||0))}</b></div>
      <div>Forced 로그아웃: <b>${app.counts?.forced_logout||0}</b></div>
      <div>Idle 로그아웃: <b>${app.counts?.idle_logout||0}</b></div>
      <div>Latency p50/p90/p95(ms): <b>${Math.round(app.latency?.p50||0)} / ${Math.round(app.latency?.p90||0)} / ${Math.round(app.latency?.p95||0)}</b></div>
    </div>
    <div style="border:1px solid #ddd;border-radius:8px;padding:12px;min-width:260px">
      <h3 style="margin:0 0 8px">Admin (최근 ${h.days}일)</h3>
      <div>Refresh 성공률: <b>${pct(adm.counts?.refresh_ok||0,(adm.counts?.refresh_ok||0)+(adm.counts?.refresh_fail||0))}</b></div>
      <div>Forced 로그아웃: <b>${adm.counts?.forced_logout||0}</b></div>
      <div>Idle 로그아웃: <b>${adm.counts?.idle_logout||0}</b></div>
      <div>Latency p50/p90/p95(ms): <b>${Math.round(adm.latency?.p50||0)} / ${Math.round(adm.latency?.p90||0)} / ${Math.round(adm.latency?.p95||0)}</b></div>
    </div>
  </div>`);
});

r.get("/metrics/session/gate", requireAdminAny, async (req,res)=>{
  // 게이트 기준(권장): refresh 성공률≥95%, p95<1500ms (App 기준)
  const days=1;
  const { fetch } = require("undici") || globalThis.fetch;
  const s = await (await fetch("http://localhost:"+ (process.env.PORT||"5902") +"/admin/metrics/session/summary",{
    headers:{"X-Admin-Key":process.env.ADMIN_KEY||""}
  })).json();
  const ok = s.app?.counts?.refresh_ok||0, fail=s.app?.counts?.refresh_fail||0;
  const rate = (ok+fail)? ok/(ok+fail):1;
  const p95 = Number(s.app?.latency?.p95||0);
  const pass = (rate>=0.95) && (p95<1500);
  res.json({ ok:true, gate:{pass, rate, p95_ms:p95, rules:{min_refresh_rate:0.95, max_p95_ms:1500}} });
});

module.exports=r;
