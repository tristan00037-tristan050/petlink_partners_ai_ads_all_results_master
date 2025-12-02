const db=require('../lib/db'); const crypto=require('crypto');

function mkIdem(batchId, bankFileId, channelId){
  return crypto.createHash('sha256').update([batchId,bankFileId,channelId].join(':'),'utf8').digest('hex');
}

async function upsertChannel({name, kind='MOCK', endpoint_url=null, headers=null, sftp_host=null, sftp_path=null, enabled=true}){
  const ins=await db.q(`
    INSERT INTO payout_channels(name,kind,endpoint_url,headers,sftp_host,sftp_path,enabled)
    VALUES($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT (name) DO UPDATE SET
      kind=EXCLUDED.kind, endpoint_url=EXCLUDED.endpoint_url, headers=EXCLUDED.headers,
      sftp_host=EXCLUDED.sftp_host, sftp_path=EXCLUDED.sftp_path, enabled=EXCLUDED.enabled,
      updated_at=now()
    RETURNING *`,
    [name, kind, endpoint_url, headers, sftp_host, sftp_path, enabled]);
  return ins.rows[0];
}
async function listChannels(){
  return (await db.q(`SELECT * FROM payout_channels WHERE enabled IS TRUE ORDER BY id DESC`)).rows;
}

async function buildBankFile(batchId, format='CSV'){
  const rows = (await db.q(`SELECT advertiser_id, amount,
           COALESCE(payee_name,'') AS payee_name,
           COALESCE(bank_code,'') AS bank_code,
           COALESCE(account_no,'') AS account_no
         FROM payout_batch_items WHERE batch_id=$1 ORDER BY amount DESC`,[batchId])).rows;

  const head = 'advertiser_id,amount,payee_name,bank_code,account_no';
  const content = [head, ...rows.map(r=>[r.advertiser_id,r.amount,r.payee_name,r.bank_code,r.account_no].join(','))].join('\n');
  const sha256 = crypto.createHash('sha256').update(content,'utf8').digest('hex');

  const ins = await db.q(`INSERT INTO payout_bank_files(batch_id,format,content,sha256,idempotency_key)
                          VALUES($1,$2,$3,$4,$5) RETURNING id, sha256, idempotency_key`,
                          [batchId, format, content, sha256, null]);
  return { id: ins.rows[0].id, sha256 };
}

async function ensureTransfersFromBatch(batchId, bankFileId){
  const existing = (await db.q(`SELECT COUNT(*)::int n FROM payout_transfers WHERE batch_id=$1`,[batchId])).rows[0]?.n||0;
  if(existing>0) return existing;
  const items = (await db.q(`SELECT advertiser_id, amount FROM payout_batch_items WHERE batch_id=$1`,[batchId])).rows;
  for(const it of items){
    await db.q(`INSERT INTO payout_transfers(batch_id,advertiser_id,amount,status,bank_file_id)
                VALUES($1,$2,$3,'PENDING',$4)`,[batchId,it.advertiser_id,it.amount,bankFileId]);
  }
  return items.length;
}

async function sendByChannel({ batchId, bankFileId, channelId }){
  const ch =(await db.q(`SELECT * FROM payout_channels WHERE id=$1 AND enabled IS TRUE`,[channelId])).rows[0];
  if(!ch) return { ok:false, code:'CHANNEL_NOT_FOUND' };
  const bf =(await db.q(`SELECT * FROM payout_bank_files WHERE id=$1 AND batch_id=$2`,[bankFileId,batchId])).rows[0];
  if(!bf) return { ok:false, code:'BANKFILE_NOT_FOUND' };

  const idem = mkIdem(batchId, bankFileId, channelId);
  const dup  = (await db.q(`SELECT 1 FROM payout_dispatch_log WHERE channel_id=$1 AND idempotency_key=$2 LIMIT 1`,[channelId, idem])).rows.length>0;
  if(dup){
    try{
      await db.q(`INSERT INTO payout_dispatch_log(batch_id,bank_file_id,channel_id,idempotency_key,status,response_code,response_body)
                  VALUES($1,$2,$3,$4,'ALREADY_SENT',200,'idem')`,[batchId, bankFileId, channelId, idem]);
    }catch(e){
      // UNIQUE constraint violation은 이미 존재하는 것이므로 무시
    }
    return { ok:true, already:true, status:'ALREADY_SENT' };
  }

  // 실제 전송 대신 DRYRUN/모의 송신(HTTPS/SFTP 모두)
  let status='DRYRUN', code=200, body='dryrun';
  // HTTPS 실제 연동은 endpoint_url이 있는 경우에만 수행 (기본 DRY)
  // 외부 의존성 없이, DRY 모드 유지
  await db.q(`INSERT INTO payout_dispatch_log(batch_id,bank_file_id,channel_id,idempotency_key,status,response_code,response_body)
              VALUES($1,$2,$3,$4,$5,$6,$7)`,
              [batchId, bankFileId, channelId, idem, status, code, body]);

  // 전송 상태 반영: PENDING -> SENT
  await db.q(`UPDATE payout_transfers SET status='SENT', updated_at=now() WHERE batch_id=$1 AND bank_file_id IS NULL`,[batchId]);
  await db.q(`UPDATE payout_transfers SET bank_file_id=$2 WHERE batch_id=$1 AND bank_file_id IS NULL`,[batchId, bankFileId]);

  return { ok:true, status };
}

async function applyReceiptSimulate(batchId, toStatus='CONFIRMED'){
  const st = String(toStatus||'CONFIRMED').toUpperCase();
  const valid = ['CONFIRMED','FAILED'];
  if(!valid.includes(st)) return { ok:false, code:'BAD_STATUS' };
  const upd=await db.q(`UPDATE payout_transfers SET status=$2, updated_at=now() WHERE batch_id=$1 AND status IN ('PENDING','SENT') RETURNING id`,[batchId, st]);
  const changed=upd.rows.length;
  try{
    await db.q(`INSERT INTO payout_dispatch_log(batch_id,bank_file_id,channel_id,idempotency_key,status,response_code,response_body)
                VALUES($1,NULL,NULL,'receipt-'||$1,'RECEIPT',200,$2)`,[batchId, JSON.stringify({status:st})]);
  }catch(e){
    // 이미 존재할 수 있음
  }
  return { ok:true, changed };
}

async function listDispatchLog(batchId){
  return (await db.q(`SELECT * FROM payout_dispatch_log WHERE batch_id=$1 ORDER BY id DESC LIMIT 200`,[batchId])).rows;
}

module.exports={ upsertChannel, listChannels, buildBankFile, ensureTransfersFromBatch, sendByChannel, applyReceiptSimulate, listDispatchLog };

