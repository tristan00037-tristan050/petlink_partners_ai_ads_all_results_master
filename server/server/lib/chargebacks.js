const db=require('../lib/db');
const crypto=require('crypto');
const fs=require('fs'); const os=require('os'); const path=require('path'); const { spawnSync }=require('child_process');

async function openCase({txid, advertiser_id, amount, reason_code, created_by}){
  const q= await db.q(
    `INSERT INTO chargeback_cases(txid,advertiser_id,amount,reason_code,created_by)
     VALUES($1,$2,$3,$4,$5) RETURNING *`,
    [txid||null, advertiser_id||null, amount||0, reason_code||null, created_by||'admin']
  );
  await db.q(`INSERT INTO chargeback_events(case_id,kind,payload) VALUES($1,'OPEN',$2)`,
             [q.rows[0].id, {txid, amount, reason_code}]);
  return q.rows[0];
}

async function addEvidence(case_id,{filename, kind, content_base64, note}){
  const buf = Buffer.from(content_base64||'', 'base64');
  const sha = crypto.createHash('sha256').update(buf).digest('hex');
  const q= await db.q(
    `INSERT INTO chargeback_evidence(case_id,filename,sha256,kind,bytes,note,content)
     VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [case_id, filename||'evidence.txt', sha, kind||'other', buf.length, note||null, buf]
  );
  await db.q(`INSERT INTO chargeback_events(case_id,kind,payload) VALUES($1,'EVIDENCE',$2)`,
             [case_id, {filename:q.rows[0].filename, sha256:sha, kind:q.rows[0].kind, bytes:buf.length}]);
  return q.rows[0];
}

async function represent(case_id,{actor}){
  await db.q(`UPDATE chargeback_cases SET status='REPRESENTED', represented_at=now(), updated_at=now() WHERE id=$1`, [case_id]);
  await db.q(`INSERT INTO chargeback_events(case_id,kind,payload) VALUES($1,'REPRESENT',$2)`,
             [case_id, {by:actor||'admin'}]);
  return {ok:true};
}

async function closeCase(case_id,{outcome, note}){
  await db.q(`UPDATE chargeback_cases SET status='CLOSED', outcome=$2, closed_at=now(), updated_at=now() WHERE id=$1`,
             [case_id, outcome||'CANCELED']);
  const c=(await db.q(`SELECT advertiser_id, amount FROM chargeback_cases WHERE id=$1`,[case_id])).rows[0]||{};
  let adj=null;
  if(outcome==='LOSE' || outcome==='WRITE_OFF'){
    adj=(await db.q(
      `INSERT INTO cbk_adjustments(case_id,advertiser_id,amount,note)
       VALUES($1,$2,$3,$4) RETURNING *`,
      [case_id, c.advertiser_id||null, -Math.abs(c.amount||0), outcome]
    )).rows[0];
  }
  await db.q(`INSERT INTO chargeback_events(case_id,kind,payload) VALUES($1,'CLOSE',$2)`,
             [case_id, {outcome, note:note||null}]);
  return {ok:true, adjustment:adj};
}

async function buildEvidenceTgz(case_id){
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(),'cbk-'));
  const rows=(await db.q(`SELECT filename,content FROM chargeback_evidence WHERE case_id=$1 ORDER BY id ASC`,[case_id])).rows;
  if(!rows.length){ fs.writeFileSync(path.join(tmp,'README.txt'),'no evidence uploaded'); }
  else{
    for(const e of rows){
      const fn = e.filename||('evidence_'+Date.now()+'.bin');
      fs.writeFileSync(path.join(tmp,fn), e.content||Buffer.from(''));
    }
  }
  const out = path.join(os.tmpdir(), `cbk_${case_id}_${Date.now()}.tgz`);
  const tar = spawnSync('tar',['-czf',out,'-C',tmp,'.'],{encoding:'utf8'});
  return { ok: tar.status===0, path: out };
}

module.exports={ openCase, addEvidence, represent, closeCase, buildEvidenceTgz };

