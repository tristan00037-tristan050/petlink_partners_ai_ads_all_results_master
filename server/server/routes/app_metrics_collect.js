const express=require("express"); const db=require("../lib/db"); const r=express.Router();

r.post("/metrics/collect", express.json(), async (req,res)=>{
  const { kind, ms, code } = req.body||{};
  if(!kind) return res.status(400).json({ok:false,code:"KIND_REQUIRED"});
  await db.q(`INSERT INTO session_events(surface,kind,ms,code) VALUES('app',$1,$2,$3)`,[String(kind), ms??null, code??null]);
  res.json({ ok:true });
});

module.exports=r;
