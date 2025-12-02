const express=require("express"); const { requireAdminAny }=require("../mw/admin_gate")||{requireAdminAny:(req,res,n)=>n()};
const { currentKids }=require("../lib/oidc_ops"); const r=express.Router();

r.get("/oidc/status", requireAdminAny, async (req,res)=>{
  const appIss=process.env.APP_OIDC_ISSUER||""; const admIss=process.env.ADMIN_OIDC_ISSUER||"";
  const appKids= appIss? await currentKids(appIss):[];
  const admKids= admIss? await currentKids(admIss):[];
  res.json({ ok:true, monitor: globalThis.__OIDC_MONITOR__||null,
             app: { issuer:appIss||null, kids:appKids, mode: appIss?"ONLINE":"OFFLINE" },
             admin:{ issuer:admIss||null, kids:admKids, mode: admIss?"ONLINE":"OFFLINE" } });
});

r.post("/oidc/refresh", requireAdminAny, async (req,res)=>{
  try{
    const mon=require("../bootstrap/oidc_monitor"); mon.start(); // 재시동성
    res.json({ ok:true, restarted:true });
  }catch(e){ res.status(500).json({ ok:false, err:String(e.message||e) }); }
});

module.exports=r;
