const store = new Map(); // key -> { exp:number, val:any }
function key(req){ return (req.method||'GET') + ' ' + (req.originalUrl||req.url); }
function get(k){ const v=store.get(k); if(!v) return null; if(Date.now()>v.exp){ store.delete(k); return null; } return v.val; }
function set(k,val,ttlSec=60){ store.set(k,{ exp: Date.now()+ttlSec*1000, val }); }
function withCache(ttlSec, loader){
  return async (req,res)=>{
    const k=key(req); const hit=get(k); 
    if(hit){ res.set('Cache-Control', `public, max-age=${ttlSec}`); return res.json(hit); }
    const data = await loader(req,res);
    set(k,data,ttlSec); res.set('Cache-Control', `public, max-age=${ttlSec}`); return res.json(data);
  };
}
module.exports = { withCache, get, set };
