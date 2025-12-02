const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const db=require('../lib/db');

async function dispatchTicket(case_id, payload){
  const url=process.env.CBK_TICKET_WEBHOOK_URL||'';
  let response={ ok:true, mock:true, code:'NO_WEBHOOK' };
  if(url){
    try{
      const r=await fetchFn(url,{method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload)});
      const body=await (async()=>{ try{ return await r.json(); }catch(_){ return { text: await r.text() }; } })();
      response={ ok:r.ok, status:r.status, body };
    }catch(e){ response={ ok:false, code:'SEND_ERROR', message: e?.message }; }
  }
  await db.q(`INSERT INTO cbk_ticket_log(case_id, kind, target_url, payload, response, created_at)
              VALUES($1,'WEBHOOK',$2,$3,$4,now())`, [case_id, url||null, payload, response]);
  return { ok:true, sent: !!url && !!response && response.ok, response };
}

module.exports={ dispatchTicket };

