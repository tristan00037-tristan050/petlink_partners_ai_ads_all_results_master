const { scanAndOpenIncidents }=require('../lib/refund_sla_watch');
const TICK=parseInt(process.env.REFUND_ALERT_TICK_SEC||'300',10);
const THR=parseInt(process.env.REFUND_SLA_MINUTES||'120',10);
async function tick(){ try{ await scanAndOpenIncidents(THR); }catch(e){ console.warn('[refund_sla] tick error', e&&e.message); } }
setInterval(tick, TICK*1000);
console.log('[refund_sla] scheduler up', { TICK, THR });
module.exports={};

