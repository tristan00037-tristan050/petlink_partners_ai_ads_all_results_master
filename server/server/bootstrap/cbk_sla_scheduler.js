const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const T=parseInt(process.env.CBK_SLA_TICK_SEC||'360',10);
const base='http://localhost:'+ (process.env.PORT||'5902'); const H={ headers:{'X-Admin-Key': process.env.ADMIN_KEY||''} };
async function tick(){ try{ await fetchFn(base+'/admin/ledger/cbk/sla/watch/run',{method:'POST',...H}); }catch(_){ } }
setInterval(tick, T*1000); console.log('[cbk_sla] scheduler up', {T});
module.exports={};

