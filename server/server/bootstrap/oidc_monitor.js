const { discovery, jwks } = require("../lib/oidc");
const { persistJwks } = require("../lib/oidc_ops");

const intSec=parseInt(process.env.OIDC_MONITOR_INTERVAL_SEC||"900",10);

async function tick(tag, iss){
  if(!iss) return { ok:false, mode:"OFFLINE" };
  try{
    const d=await discovery(iss); const k=await jwks(iss);
    const r=await persistJwks(iss, k);
    return { ok:true, mode:"ONLINE", issuer:iss, kids:r.kids };
  }catch(e){ return { ok:false, mode:"ERROR", err:String(e.message||e) }; }
}

function start(){
  const appIss=process.env.APP_OIDC_ISSUER||"";
  const admIss=process.env.ADMIN_OIDC_ISSUER||"";
  setTimeout(()=>{ tick("init-app",appIss); tick("init-adm",admIss); }, 1000);
  setInterval(()=>{ tick("loop-app",appIss); tick("loop-adm",admIss); }, intSec*1000);
  globalThis.__OIDC_MONITOR__={ start_ts:Date.now(), interval:intSec };
}

module.exports={ start };
