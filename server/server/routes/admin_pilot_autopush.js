const express = require("express");
const { adminCORS } = (function(){ try { return require("../mw/cors_split"); } catch(e){ return {}; } })();

let requireAdminAny; try { requireAdminAny = require("../mw/admin_gate").requireAdminAny; } catch(e) { requireAdminAny = null; }

const r = express.Router();
const pilot = require("../lib/pilot_report");

function guard(req,res,next){
  if (requireAdminAny) return requireAdminAny(req,res,next);
  const k = req.get("X-Admin-Key"); if (k && k === (process.env.ADMIN_KEY||"")) return next();
  return res.status(401).json({ ok:false, code:"ADMIN_AUTH_REQUIRED" });
}

async function postWebhook(payload){
  const url = process.env.PILOT_WEBHOOK_URL || "";
  const fetchFn = (global.fetch || require("undici").fetch || globalThis.fetch);
  
  if (!url) { console.log("[pilot:webhook]", JSON.stringify(payload)); return { ok:false, posted:false, code:"NO_WEBHOOK" }; }
  
  try{
    const res = await fetchFn(url, { method:"POST", headers:{"Content-Type":"application/json"}, body: JSON.stringify(payload) });
    return { ok: res.ok, posted: res.ok };
  }catch(e){ return { ok:false, posted:false, code:"SEND_ERROR" }; }
}

r.get("/pilot/autopush/preview", adminCORS||((req,res,next)=>next()), guard, async (req,res)=>{
  try { const j = await pilot.generate(); res.json({ ok:true, preview:j }); }
  catch(e){ res.status(500).json({ ok:false, code:String(e.message||e) }); }
});

r.post("/pilot/autopush/run", adminCORS||((req,res,next)=>next()), guard, express.json(), async (req,res)=>{
  try{
    const j = await pilot.generate();
    const payload = {
      title: "Pilot Go/No-Go",
      ts: j.ts,
      overall: j.pilot?.go ? "GO" : "HOLD",
      payments: j.metrics?.payments,
      session_gate: j.metrics?.session_gate,
      thresholds: j.thresholds
    };
    const sent = await postWebhook(payload);
    res.json({ ok:true, posted: !!sent.posted, payload });
  }catch(e){ res.status(500).json({ ok:false, code:String(e.message||e) }); }
});

let cronEnabled = (String(process.env.PILOT_AUTOPUSH_CRON||"1") === "1");
let cronMin = parseInt(process.env.PILOT_AUTOPUSH_CRON_MIN||"30",10);
let _timer = null;

function startCron(){
  if (!cronEnabled) return;
  if (_timer) clearInterval(_timer);
  _timer = setInterval(async ()=>{
    try{
      const now = new Date();
      if (now.getMinutes() !== cronMin) return; // 매시 정각+오프셋
      
      const j = await pilot.generate();
      const payload = {
        title: "Pilot Go/No-Go (hourly)",
        ts: j.ts, overall: j.pilot?.go ? "GO" : "HOLD",
        payments: j.metrics?.payments, session_gate: j.metrics?.session_gate,
        thresholds: j.thresholds
      };
      await postWebhook(payload);
      console.log("[pilot:cron] posted at", now.toISOString());
    }catch(e){ console.warn("[pilot:cron] error", e && e.message); }
  }, 30 * 1000); // 30초마다 분 체크
}

startCron();

r.get("/pilot/autopush/status", adminCORS||((req,res,next)=>next()), guard, (req,res)=>{
  res.json({ ok:true, enabled: cronEnabled, minute: cronMin });
});

// r9.6: 주/월 템플릿 엔드포인트
const templates = require('../lib/pilot_templates');
r.get("/pilot/templates.json", adminCORS||((req,res,next)=>next()), guard, async (req,res)=>{
  const period = (req.query.period||'weekly').toLowerCase();
  if(period!=='weekly' && period!=='monthly') return res.status(400).json({ok:false,code:'INVALID_PERIOD'});
  try{
    const t = await templates.build(period);
    res.json(t);
  }catch(e){ res.status(500).json({ok:false,code:String(e.message||e)}); }
});

// r9.6: 주/월 Autopush 실행
r.post("/pilot/autopush/run-weekly", adminCORS||((req,res,next)=>next()), guard, express.json(), async (req,res)=>{
  try{
    const t = await templates.build('weekly');
    const payload = { title: t.subject, ts: new Date().toISOString(), overall: t.overall.go ? 'GO' : 'HOLD', metrics: t.metrics, markdown: t.markdown };
    const sent = await postWebhook(payload);
    res.json({ ok:true, posted: !!sent.posted, payload, version: t.version });
  }catch(e){ res.status(500).json({ ok:false, code:String(e.message||e) }); }
});

r.post("/pilot/autopush/run-monthly", adminCORS||((req,res,next)=>next()), guard, express.json(), async (req,res)=>{
  try{
    const t = await templates.build('monthly');
    const payload = { title: t.subject, ts: new Date().toISOString(), overall: t.overall.go ? 'GO' : 'HOLD', metrics: t.metrics, markdown: t.markdown };
    const sent = await postWebhook(payload);
    res.json({ ok:true, posted: !!sent.posted, payload, version: t.version });
  }catch(e){ res.status(500).json({ ok:false, code:String(e.message||e) }); }
});

module.exports = r;
