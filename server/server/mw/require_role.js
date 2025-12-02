const db = require("../lib/db");
function requireAny(roles, opts={}){
  const onlyMethods = (opts.onlyMethods||[]).map(m=>m.toUpperCase());
  const bypass = (req)=> onlyMethods.length && !onlyMethods.includes(req.method.toUpperCase());
  return async (req,res,next)=>{
    if (bypass(req)) return next();
    if (!req.user || !req.user.user_id) return res.status(401).json({ ok:false, code:"AUTH_REQUIRED" });
    const q = await db.q(`SELECT 1 FROM app_user_roles WHERE user_id=$1 AND role_code = ANY($2::text[]) LIMIT 1`,
                          [req.user.user_id, roles]);
    if (!q.rows.length) return res.status(403).json({ ok:false, code:"FORBIDDEN" });
    next();
  };
}
module.exports = { requireAny };
