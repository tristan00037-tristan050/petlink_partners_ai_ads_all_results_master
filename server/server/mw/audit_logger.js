const db = require("../lib/db");
module.exports = function(req,res,next){
  const start = Date.now();
  const actor = req.user?.user_id ? { type:"app", id:req.user.user_id, adv:req.user.advertiser_id } :
                 (req.get("X-Admin-Key") ? { type:"admin", id:null, adv:null } : { type:"system", id:null, adv:null });
  const reqId = req.req_id || req.get("X-Request-Id") || null;
  res.on("finish", async ()=>{
    try{
      await db.q(`INSERT INTO audit_logs(ts, actor_type, actor_id, advertiser_id, method, path, status, req_id, ip, meta)
                  VALUES (now(), $1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [actor.type, actor.id, actor.adv||null, req.method, req.path, res.statusCode, reqId, req.ip, JSON.stringify({ms:Date.now()-start})]);
    }catch(e){ /* swallow */ }
  });
  next();
}
