const db=require('../lib/db');
const crypto=require('crypto');
const fs=require('fs'); const os=require('os'); const path=require('path');
function genTxid(prefix='TX'){ return prefix+'_'+Math.random().toString(36).slice(2); }

async function ingestFromSources(days=7){
  // ad_payments → live_ledger
  try{
    const q=await db.q(`
      SELECT invoice_no AS ref, advertiser_id, amount, status, COALESCE(env,'sbx') env, created_at
      FROM ad_payments
      WHERE created_at >= now() - ($1||' days')::interval
    `,[days]);
    for(const r of q.rows){
      if(r.status!=='CAPTURED') continue;
      const txid='CAP_'+r.ref;
      await db.q(`
        INSERT INTO live_ledger(txid,advertiser_id,env,kind,parent_txid,amount,status,external_id,meta,event_at)
        VALUES($1,$2,$3,'CAPTURE',NULL,$4,'SETTLED',$5,$6,$7)
        ON CONFLICT (txid) DO NOTHING
      `,[txid,r.advertiser_id,r.env,Number(r.amount),r.ref,{source:'ad_payments'},r.created_at]);
    }
  }catch(_){}
  // live_billing_journal → live_ledger (옵션)
  try{
    const q=await db.q(`
      SELECT id::text AS ref, advertiser_id, amount, result, created_at
      FROM live_billing_journal
      WHERE created_at >= now() - ($1||' days')::interval
    `,[days]);
    for(const r of q.rows){
      if(r.result!=='LIVE_OK') continue;
      const txid='LJ_'+r.ref;
      await db.q(`
        INSERT INTO live_ledger(txid,advertiser_id,env,kind,amount,status,external_id,meta,event_at)
        VALUES($1,$2,'live','CAPTURE',$3,'SETTLED',$4,$5,$6)
        ON CONFLICT (txid) DO NOTHING
      `,[txid,r.advertiser_id,Number(r.amount),r.ref,{source:'live_journal'},r.created_at]);
    }
  }catch(_){}
  return { ok:true };
}

async function requestRefund({ ledger_txid, advertiser_id, amount, reason, actor }){
  const q=await db.q(`INSERT INTO refund_requests(ledger_txid,advertiser_id,amount,reason,actor,status,updated_at)
                      VALUES($1,$2,$3,$4,$5,'REQUESTED',now()) RETURNING id`,
                      [ledger_txid,advertiser_id,amount,reason||'',actor||'admin']);
  return { ok:true, id:q.rows[0].id };
}
async function approveRefund({ id, approver, reject=false }){
  const status = reject ? 'REJECTED' : 'APPROVED';
  await db.q(`UPDATE refund_requests SET status=$2, updated_at=now(), actor=COALESCE(actor,$3) WHERE id=$1`,[id,status,approver||'approver']);
  return { ok:true, status };
}
async function execRefund({ id }){
  const rq=(await db.q(`SELECT * FROM refund_requests WHERE id=$1`,[id])).rows[0];
  if(!rq || rq.status!=='APPROVED') return { ok:false, code:'NOT_APPROVED' };
  const rcap=(await db.q(`SELECT * FROM live_ledger WHERE txid=$1`,[rq.ledger_txid])).rows[0];
  const txid=genTxid('RF');
  await db.q(`INSERT INTO live_ledger(txid,advertiser_id,env,kind,parent_txid,amount,status,meta)
              VALUES($1,$2,$3,'REFUND',$4,$5,'SETTLED',$6)`,
              [txid, rq.advertiser_id || rcap?.advertiser_id, rcap?.env||'live', rq.ledger_txid, -Math.abs(Number(rq.amount)), { reason: rq.reason }]);
  await db.q(`UPDATE refund_requests SET status='EXECUTED', updated_at=now() WHERE id=$1`,[id]);
  return { ok:true, txid };
}

async function runRecon(days=7){
  const job=(await db.q(`INSERT INTO recon_jobs(status) VALUES('RUNNING') RETURNING id`)).rows[0].id;
  let diffs=0;
  try{
    const pay=(await db.q(`
      SELECT invoice_no AS ref, SUM(CASE WHEN status='CAPTURED' THEN amount ELSE 0 END)::int amt
      FROM ad_payments WHERE created_at >= now()-($1||' days')::interval GROUP BY 1`,[days])).rows;
    for(const p of pay){
      const led=(await db.q(`SELECT SUM(amount)::int amt FROM live_ledger WHERE txid=$1`,['CAP_'+p.ref])).rows[0]?.amt||0;
      if(Number(led)!==Number(p.amt)){
        await db.q(`INSERT INTO recon_diffs(job_id,side,ref_id,amount,info) VALUES($1,'PAYMENTS',$2,$3,$4)`,
                   [job,p.ref,Number(p.amt),{ ledger: led }]); diffs++;
      }
    }
  }catch(_){}
  try{
    const lj=(await db.q(`SELECT id::text AS ref, amount::int amt
                          FROM live_billing_journal WHERE created_at >= now()-($1||' days')::interval`,[days])).rows;
    for(const x of lj){
      const led=(await db.q(`SELECT SUM(amount)::int amt FROM live_ledger WHERE txid=$1`,['LJ_'+x.ref])).rows[0]?.amt||0;
      if(Number(led)!==Number(x.amt)){
        await db.q(`INSERT INTO recon_diffs(job_id,side,ref_id,amount,info) VALUES($1,'LIVE_JOURNAL',$2,$3,$4)`,
                   [job,x.ref,Number(x.amt),{ ledger: led }]); diffs++;
      }
    }
  }catch(_){}
  await db.q(`UPDATE recon_jobs SET status=$2, ended_at=now(), note=$3 WHERE id=$1`,[job, (diffs? 'DIFF':'OK'), `diffs=${diffs}`]);
  return { ok:true, job, diffs };
}

function sha256(buf){ return crypto.createHash('sha256').update(buf).digest('hex'); }
async function buildEvidenceBundle({ ledger_txid, outdir }){
  const tx=(await db.q(`SELECT * FROM live_ledger WHERE txid=$1`,[ledger_txid])).rows[0];
  if(!tx) return { ok:false, code:'NOT_FOUND' };
  const tmp = outdir || fs.mkdtempSync(path.join(os.tmpdir(),'evi_'));
  const summary={ tx, proof: { signed:false, generator:'r11.0-ci-lite' } };
  fs.writeFileSync(path.join(tmp,'ledger.json'), JSON.stringify(tx,null,2));
  fs.writeFileSync(path.join(tmp,'summary.json'), JSON.stringify(summary,null,2));
  const out=path.join(os.tmpdir(), `evidence_${ledger_txid.replace(/[^a-zA-Z0-9]/g,'_')}_${Date.now()}.tgz`);
  const { spawnSync }=require('child_process');
  const tar=spawnSync('tar',['-czf',out,'-C',tmp,'.'],{encoding:'utf8'});
  if(tar.status!==0){ 
    // tar가 없으면 간단한 압축 없이 JSON만 저장
    const jsonOut=path.join(os.tmpdir(), `evidence_${ledger_txid.replace(/[^a-zA-Z0-9]/g,'_')}_${Date.now()}.json`);
    fs.writeFileSync(jsonOut, JSON.stringify({ tx, summary },null,2));
    const sh=sha256(fs.readFileSync(jsonOut));
    await db.q(`INSERT INTO ci_evidence(ledger_txid,kind,bundle_path,sha256) VALUES($1,$2,$3,$4)`,
               [ledger_txid, tx.kind, jsonOut, sh ]);
    return { ok:true, path: jsonOut, sha256: sh };
  }
  const sh=sha256(fs.readFileSync(out));
  await db.q(`INSERT INTO ci_evidence(ledger_txid,kind,bundle_path,sha256) VALUES($1,$2,$3,$4)`,
             [ledger_txid, tx.kind, out, sh ]);
  return { ok:true, path: out, sha256: sh };
}
module.exports={ ingestFromSources, requestRefund, approveRefund, execRefund, runRecon, buildEvidenceBundle };

