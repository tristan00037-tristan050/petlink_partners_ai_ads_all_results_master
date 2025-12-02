const crypto=require("crypto"); const SEC=process.env.ADMIN_JWT_SECRET||"admin-dev-secret";

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

function requireAdminAny(req,res,next){
  const k=req.get("X-Admin-Key"); if(k && k===(process.env.ADMIN_KEY||"")){ req.admin={mode:"key",sub:"root@local",roles:["OWNER"]}; return next(); }
  const h=req.get("Authorization")||""; if(h.startsWith("Bearer ")){ const p=verifyJWT(h.slice(7),SEC); if(p){ req.admin={mode:"jwt",sub:p.sub,roles:p.roles||[]}; return next(); } return res.status(401).json({ok:false,code:"ADMIN_JWT_INVALID"}); }
  return res.status(401).json({ok:false,code:"ADMIN_AUTH_REQUIRED"});
}
module.exports={ requireAdminAny };
