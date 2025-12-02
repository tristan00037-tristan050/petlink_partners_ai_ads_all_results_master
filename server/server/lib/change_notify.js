const ch = (function(){ try{ return require('./alerts_channels'); }catch(_){ return null; } })();
async function send(kind, payload){
  if(!ch || !ch.notifyWithSeverity){ console.log('[change:mock]', kind, payload); return { ok:false, code:'NO_WEBHOOK' }; }
  const sev = (kind==='APPLY_DRYRUN' || kind==='CREATED') ? 'info' : (kind==='APPROVED' ? 'warn' : 'critical');
  return ch.notifyWithSeverity(sev, 'PROD_CHANGE_'+kind, payload);
}
module.exports = { send };

