const crypto = require("crypto");
const secret = process.env.APP_JWT_SECRET || "dev";
const b64u = (s)=> Buffer.from(s).toString("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const b64uJson = (o)=> b64u(JSON.stringify(o));
function sign(payload, ttlSec=900){ // access 15m
  const now = Math.floor(Date.now()/1000);
  const p = { ...payload, iat: now, exp: now + ttlSec };
  const seg = b64uJson({ alg:"HS256", typ:"JWT" })+"."+b64uJson(p);
  const sig = crypto.createHmac("sha256", secret).update(seg).digest("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
  return seg+"."+sig;
}
function decode(token){
  const [h,p] = String(token||"").split(".");
  if(!h||!p) return null;
  try { return JSON.parse(Buffer.from(p.replace(/-/g,"+").replace(/_/g,"/"),"base64").toString("utf8")); }
  catch { return null; }
}
function verify(token){
  const [h,p,s]=String(token||"").split(".");
  if(!h||!p||!s) return null;
  const expSig = crypto.createHmac("sha256", secret).update(h+"."+p).digest("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
  if (!crypto.timingSafeEqual(Buffer.from(expSig), Buffer.from(s))) return null;
  const claims = decode(token); const now = Math.floor(Date.now()/1000);
  if(!claims || (claims.exp && now > claims.exp)) return null;
  return claims;
}
module.exports = { sign, verify, decode };
