const { verify } = require("../lib/auth/jwt");
module.exports = function(req,res,next){
  const m = (req.get("Authorization")||"").match(/^Bearer\s+(.+)$/i);
  if(!m) return res.status(401).json({ ok:false, code:"AUTH_REQUIRED" });
  const claims = verify(m[1]); if(!claims) return res.status(401).json({ ok:false, code:"AUTH_INVALID" });
  req.user = claims; next();
}
