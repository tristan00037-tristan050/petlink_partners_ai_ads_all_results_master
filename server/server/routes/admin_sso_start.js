const express=require("express"); const r=express.Router();
const { discovery } = require("../lib/oidc");
const { randomBytes } = require("crypto");
function hex(n=16){ return randomBytes(n).toString("hex"); }

r.get("/admin/auth/oidc/start", async (req,res)=>{
  const iss=process.env.ADMIN_OIDC_ISSUER||""; const client=process.env.ADMIN_OIDC_CLIENT_ID||""; const redirect=process.env.ADMIN_OIDC_REDIRECT||"";
  const force = (req.query.force==="1" || req.query.prompt==="login");
  const maxAge = Number.isFinite(+req.query.max_age) ? String(+req.query.max_age) : "120";

  if (req.query.dry==="1") {
    return res.json({ ok:true, prompt: "login", max_age: maxAge }); // Admin은 항상 강제 로그인 UX 가정
  }

  if(!iss||!client||!redirect) return res.status(503).send("OIDC_OFFLINE");
  const d=await discovery(iss);
  const state=hex(16), nonce=hex(16);
  res.cookie("admin_state", state, { httpOnly:false, sameSite:"Lax" });
  res.cookie("admin_nonce", nonce, { httpOnly:false, sameSite:"Lax" });
  const url=new URL(d.authorization_endpoint);
  url.searchParams.set("response_type","code");
  url.searchParams.set("client_id",client);
  url.searchParams.set("redirect_uri",redirect);
  url.searchParams.set("scope","openid email profile");
  url.searchParams.set("state",state);
  url.searchParams.set("nonce",nonce);
  url.searchParams.set("prompt","login");
  url.searchParams.set("max_age", maxAge);
  return res.redirect(url.toString());
});

module.exports=r;
