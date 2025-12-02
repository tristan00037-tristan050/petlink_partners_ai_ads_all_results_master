const express=require("express"); const r=express.Router();
const { discovery } = require("../lib/oidc");
const { randomBytes } = require("crypto");

function hex(n=16){ return randomBytes(n).toString("hex"); }

r.get("/auth/oidc/start", async (req,res)=>{
  const iss=process.env.APP_OIDC_ISSUER||""; const client=process.env.APP_OIDC_CLIENT_ID||""; const redirect=process.env.APP_OIDC_REDIRECT||"";
  const force = (req.query.force==="1" || req.query.prompt==="login");
  const maxAge = Number.isFinite(+req.query.max_age) ? String(+req.query.max_age) : "300";

  // dry=1이면 리다이렉트 대신 파라미터 JSON 반환(환경 미주입이어도 검증 가능)
  if (req.query.dry==="1") {
    return res.json({ ok:true, prompt: force?"login":"select_account", max_age: maxAge });
  }

  if(!iss||!client||!redirect) return res.status(503).send("OIDC_OFFLINE");
  const d=await discovery(iss);
  const state=hex(16), nonce=hex(16);
  res.cookie("app_state", state, { httpOnly:false, sameSite:"Lax" });
  res.cookie("app_nonce", nonce, { httpOnly:false, sameSite:"Lax" });
  const url=new URL(d.authorization_endpoint);
  url.searchParams.set("response_type","code");
  url.searchParams.set("client_id",client);
  url.searchParams.set("redirect_uri",redirect);
  url.searchParams.set("scope","openid email profile");
  url.searchParams.set("state",state);
  url.searchParams.set("nonce",nonce);
  url.searchParams.set("prompt", force?"login":"select_account");
  url.searchParams.set("max_age", maxAge);
  return res.redirect(url.toString());
});

module.exports=r;
