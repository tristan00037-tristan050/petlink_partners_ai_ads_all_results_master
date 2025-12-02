const db=require('../lib/db');
let alerts=null; try{ alerts=require('../lib/alerts_channels'); }catch(_){ alerts=null; }

async function scanAndOpenIncidents(thrMin=120){
  const q=await db.q(`
    SELECT id, approved_at, now() AS now
    FROM refund_requests
    WHERE status IN ('APPROVED','approved')
      AND executed_at IS NULL
      AND approved_at IS NOT NULL
      AND approved_at < now()-($1||' minutes')::interval
    ORDER BY approved_at ASC
    LIMIT 200
  `,[thrMin]);
  let opened=0;
  for(const r of q.rows){
    const exists=(await db.q(`SELECT 1 FROM refund_incidents WHERE refund_id=$1 AND (closed IS NOT TRUE OR closed IS NULL) LIMIT 1`,[r.id])).rows.length>0;
    if(exists) continue;
    const sev = 'critical'; // SLA 초과는 기본 critical
    await db.q(`INSERT INTO refund_incidents(refund_id,severity,opened_at) VALUES($1,$2,now())`,[r.id, sev]);
    opened++;
    if(alerts){
      const url=process.env.LEDGER_ALERT_CRIT_URL || process.env.PILOT_WEBHOOK_CRIT_URL || process.env.PILOT_WEBHOOK_URL || '';
      try{ await alerts.notifyWithSeverity(sev,'REFUND_SLA_BREACH',{ refund_id:r.id, threshold_min: thrMin }); }catch(_){}
    } else {
      console.log('[refund_sla] breach open', r.id);
    }
  }
  return { ok:true, opened };
}
module.exports={ scanAndOpenIncidents };

