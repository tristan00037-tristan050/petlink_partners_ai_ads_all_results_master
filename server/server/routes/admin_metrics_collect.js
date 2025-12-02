const express=require("express"); const db=require("../lib/db");
const admin = require("../mw/admin_gate")||require("../mw/admin");
const r=express.Router();
const requireAdminAny = (admin.requireAdminAny || admin.requireAdmin);

// 세션 이벤트(어드민 표면) 수집
r.post("/metrics/collect", requireAdminAny, express.json(), async (req,res)=>{
  const { kind, ms, code } = req.body||{};
  if(!kind) return res.status(400).json({ok:false,code:"KIND_REQUIRED"});
  await db.q(`INSERT INTO session_events(surface,kind,ms,code) VALUES('admin',$1,$2,$3)`,[String(kind), ms??null, code??null]);
  res.json({ ok:true });
});

// OIDC 이벤트 수집
r.post("/metrics/oidc/collect", requireAdminAny, express.json(), async (req,res)=>{
  const { surface="admin", event, code, latency_ms } = req.body||{};
  if(!event) return res.status(400).json({ok:false,code:"EVENT_REQUIRED"});
  const sf = (String(surface)==="app"?"app":"admin");
  await db.q(`INSERT INTO oidc_events(surface,event,code,latency_ms) VALUES($1,$2,$3,$4)`,[sf,String(event), code??null, latency_ms??null]);
  res.json({ ok:true });
});

module.exports=r;
