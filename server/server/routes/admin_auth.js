const express=require("express"); const crypto=require("crypto"); const { requireAdminAny }=require("../mw/admin_gate");
const SEC=process.env.ADMIN_JWT_SECRET||"admin-dev-secret"; const r=express.Router();
let BOOT={ email:"admin@local", password:"admin123", roles:["OWNER"] };

function signJWT(payload,ttlSec=900){
  const now=Math.floor(Date.now()/1000);
  const p={...payload,iat:now,exp:now+ttlSec};
  const b64u=(s)=>Buffer.from(s).toString("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
  const h=b64u(JSON.stringify({alg:"HS256",typ:"JWT"}));
  const pl=b64u(JSON.stringify(p));
  const sig=crypto.createHmac("sha256",SEC).update(h+"."+pl).digest("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
  return h+"."+pl+"."+sig;
}

function verifyJWT(token,secret){
  const [h,p,s]=String(token||"").split(".");
  if(!h||!p||!s) return null;
  try{
    const expSig=crypto.createHmac("sha256",secret).update(h+"."+p).digest("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
    if(!crypto.timingSafeEqual(Buffer.from(expSig),Buffer.from(s))) return null;
    const claims=JSON.parse(Buffer.from(p.replace(/-/g,"+").replace(/_/g,"/"),"base64").toString("utf8"));
    const now=Math.floor(Date.now()/1000);
    if(claims.exp && now>claims.exp) return null;
    return claims;
  }catch{ return null; }
}

r.post("/auth/bootstrap", requireAdminAny, express.json(), (req,res)=>{ const {email,password,roles}=req.body||{};
  if(!email||!password) return res.status(400).json({ok:false,code:"FIELDS_REQUIRED"}); BOOT={ email,password,roles:Array.isArray(roles)&&roles.length?roles:["OWNER"] }; return res.json({ok:true});
});

r.post("/auth/login", express.json(), (req,res)=>{ const {email,password}=req.body||{};
  if(email!==BOOT.email || password!==BOOT.password) return res.status(401).json({ok:false,code:"LOGIN_FAILED"});
  const access_token=signJWT({sub:email,roles:BOOT.roles,typ:"access"},900);
  const refresh_token=signJWT({sub:email,typ:"refresh"},30*24*3600);
  return res.json({ok:true,access_token,refresh_token});
});

r.post("/auth/refresh", express.json(), (req,res)=>{ const {refresh_token}=req.body||{};
  const p=verifyJWT(refresh_token,SEC); if(!p || p.typ!=="refresh") return res.status(401).json({ok:false,code:"INVALID_TOKEN"});
  const access_token=signJWT({sub:p.sub,roles:BOOT.roles||[],typ:"access"},900); return res.json({ok:true,access_token});
});

module.exports=r;
