const db=require('../lib/db'); const crypto=require('crypto');
const fs=require('fs'); const os=require('os'); const path=require('path'); const { spawnSync }=require('child_process');
let alertsCh=null; try{ alertsCh=require('../lib/alerts_channels'); }catch(_){ alertsCh=null; }
const cbkLib=require('./chargebacks'); // r11.8

function periodRange(period){ // 'YYYY-MM' -> [from,to)
  const [y,m]=String(period).split('-').map(x=>parseInt(x,10));
  const from=new Date(Date.UTC(y,m-1,1,0,0,0)); const to=new Date(Date.UTC(m===12?y+1:y, m===12?1:m, 1,0,0,0));
  return { from, to };
}

async function computeImpact(period){
  const {from,to}=periodRange(period);
  const q=await db.q(`
    SELECT c.advertiser_id, COALESCE(SUM(a.amount),0)::int AS cbk_amount, COUNT(*)::int AS cases
      FROM cbk_adjustments a
      JOIN chargeback_cases c ON c.id=a.case_id
     WHERE c.closed_at >= $1 AND c.closed_at < $2
     GROUP BY 1 ORDER BY 1`, [from, to]);
  return { ok:true, period, items:q.rows };
}

async function upsertImpactAndTags(period){
  const {from,to}=periodRange(period);
  // impact upsert
  const agg=await computeImpact(period);
  for(const r of (agg.items||[])){
    await db.q(`INSERT INTO ledger_period_cbk_impact(period,advertiser_id,cbk_amount,cases)
                VALUES($1,$2,$3,$4)
                ON CONFLICT(period,advertiser_id) DO UPDATE
                SET cbk_amount=EXCLUDED.cbk_amount, cases=EXCLUDED.cases`,
                [period, r.advertiser_id, r.cbk_amount, r.cases]);
  }
  // tx tags: CBK
  await db.q(`
    INSERT INTO ledger_tx_tags(txid,tags,updated_at)
    SELECT DISTINCT c.txid, ARRAY['CBK'], now()
      FROM chargeback_cases c
     WHERE c.closed_at >= $1 AND c.closed_at < $2 AND c.txid IS NOT NULL
    ON CONFLICT(txid) DO UPDATE SET
      tags = (SELECT ARRAY(SELECT DISTINCT UNNEST(COALESCE(ledger_tx_tags.tags,'{}'::text[]) || ARRAY['CBK']))),
      updated_at = now()`, [from,to]);
  return { ok:true, period, upserted: (agg.items||[]).length };
}

async function slaScan(thrDays=7){
  const q=await db.q(`
    WITH no_ev AS (
      SELECT c.id
        FROM chargeback_cases c
        LEFT JOIN chargeback_evidence e ON e.case_id=c.id
       WHERE c.status='OPEN'
         AND c.opened_at < now()-($1||' days')::interval
       GROUP BY c.id HAVING COUNT(e.id)=0
    )
    INSERT INTO cbk_incidents(case_id,kind,note)
    SELECT id,'SLA_MISS_EVIDENCE','no evidence within threshold'
      FROM no_ev
     WHERE NOT EXISTS (SELECT 1 FROM cbk_incidents i WHERE i.case_id=no_ev.id AND i.acked IS NOT TRUE)
    RETURNING id,case_id`, [thrDays]);
  if(alertsCh && q.rows.length) try{ await alertsCh.notifyWithSeverity('warn','CBK_SLA_OPEN',{ count:q.rows.length, thrDays }); }catch(_){}
  return { ok:true, created:q.rows.length };
}

async function listSlaOpen(){ const rows=(await db.q(`SELECT * FROM cbk_incidents WHERE acked IS NOT TRUE ORDER BY opened_at DESC LIMIT 200`)).rows; return { ok:true, items:rows }; }
async function ackIncident(id,by){ await db.q(`UPDATE cbk_incidents SET acked=TRUE, acked_by=$2, acked_at=now() WHERE id=$1`,[id,by||'admin']); return { ok:true }; }

async function evidenceManifest(case_id){
  const e=(await db.q(`SELECT filename,sha256,kind,bytes,created_at FROM chargeback_evidence WHERE case_id=$1 ORDER BY id ASC`,[case_id])).rows;
  const tmp = await cbkLib.buildEvidenceTgz(case_id);
  let tarSha=null, size=0;
  if(tmp?.ok){
    const buf=fs.readFileSync(tmp.path); size=buf.length; tarSha=crypto.createHash('sha256').update(buf).digest('hex');
  }
  return { ok:true, case_id, files:e, archive:{ sha256: tarSha, bytes:size } };
}

module.exports={ computeImpact, upsertImpactAndTags, slaScan, listSlaOpen, ackIncident, evidenceManifest };

