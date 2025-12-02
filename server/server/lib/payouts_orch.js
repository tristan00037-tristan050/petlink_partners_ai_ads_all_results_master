const db=require('../lib/db');
let alerts=null; try{ alerts=require('../lib/alerts_channels'); }catch(_){ alerts=null; }

/** r11.1 스냅샷 우선 로딩 */
async function loadSnapshot(period){
  try{
    const q=await db.q(
      `SELECT advertiser_id, net::bigint AS amount
         FROM ledger_period_snapshots
        WHERE period=$1 AND net>0
        ORDER BY net DESC`, [period]);
    if(q.rows.length) return { ok:true, source:'snapshot', items:q.rows };
  }catch(_) {}
  return { ok:false, source:'none', items:[] };
}

/** 스냅샷이 없을 때 Fallback — live_ledger 집계 */
async function computeFallback(period){
  try{
    const [y,m]=String(period||'').split('-').map(n=>parseInt(n,10));
    if(!y || !m) return { ok:true, source:'fallback', items:[] };
    const first=`${y}-${String(m).padStart(2,'0')}-01`;
    const q=await db.q(
      `SELECT advertiser_id, SUM(amount)::bigint AS amount
         FROM live_ledger
        WHERE event_at >= $1::date
          AND event_at < ($1::date + INTERVAL '1 month')
        GROUP BY 1 HAVING SUM(amount)>0
        ORDER BY 2 DESC`, [first]);
    return { ok:true, source:'fallback', items:q.rows };
  }catch(_){ return { ok:true, source:'fallback', items:[] }; }
}

async function preview(period){
  const s=await loadSnapshot(period);
  if(s.ok) return { ok:true, period, source:s.source, items:s.items };
  const f=await computeFallback(period);
  return { ok:true, period, source:f.source, items:f.items };
}

async function build(period,{commit=false, actor='admin', note=null}={}){
  const p=await preview(period);
  const items=p.items||[];
  const total=items.reduce((a,x)=>a+(+x.amount||0),0);
  if(!commit){ return { ok:true, dryrun:true, period, count:items.length, total, sample:items.slice(0,50) }; }
  const ins=await db.q(
    `INSERT INTO payout_batches(period,status,total_amount,item_count,dryrun,created_by,note,created_at,updated_at)
     VALUES($1,'draft',$2,$3,false,$4,$5,now(),now())
     RETURNING id`,
     [period,total,items.length,actor,note]);
  const bid=ins.rows[0].id;
  for(const it of items){
    await db.q(
      `INSERT INTO payout_batch_items(batch_id,advertiser_id,amount,payee_name,bank_code,account_no,meta)
       VALUES($1,$2,$3,NULL,NULL,NULL,$4)`,
      [bid,it.advertiser_id,it.amount,JSON.stringify({source:p.source})]);
  }
  return { ok:true, dryrun:false, batch_id:bid, period, count:items.length, total };
}

async function approve(batch_id,{approver='admin2'}={}){
  const q=await db.q(`SELECT created_by,status FROM payout_batches WHERE id=$1`,[batch_id]);
  if(!q.rows.length) return { ok:false, code:'NOT_FOUND' };
  const createdBy=q.rows[0].created_by||'';
  if(createdBy && createdBy===approver) return { ok:false, code:'SOD_VIOLATION' };
  await db.q(
    `UPDATE payout_batches
        SET status='approved', approved_by=$2, approved_at=now(), updated_at=now()
      WHERE id=$1`,
    [batch_id,approver]);
  return { ok:true, status:'approved' };
}

async function send(batch_id,{webhookUrl=null}={}){
  // SBX: 실제 은행 송금 없음. 상태 전이 + 웹훅 로그 기록
  const payload={ batch_id, mode:'SBX', sent_at:new Date().toISOString() };
  let out={ ok:false, status:'mock' };
  const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
  if(webhookUrl && fetchFn){
    try{
      const r=await fetchFn(webhookUrl,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
      out={ ok:r.ok, status:(r.ok?'200':'HTTP') };
    }catch(e){ out={ ok:false, status:'SEND_ERR', error:e?.message }; }
  }
  await db.q(`UPDATE payout_batches SET status='sent', updated_at=now() WHERE id=$1`,[batch_id]);
  await db.q(`INSERT INTO payout_webhook_log(batch_id,status,response) VALUES($1,$2,$3)`,
             [batch_id, out.status, JSON.stringify({ ok:out.ok, ...payload })]);
  if(alerts){ try{ await alerts.notifyWithSeverity(out.ok?'info':'warn','PAYOUT_SENT',payload); }catch(_){} }
  return { ok:true, status:'sent', webhook:out };
}

function _csv(rows){
  const hdr=['advertiser_id','amount','payee_name','bank_code','account_no'].join(',');
  const esc=v=> (v==null?'':String(v).replace(/"/g,'""'));
  const body=(rows||[]).map(r=>[`"${esc(r.advertiser_id)}"`,`"${esc(r.amount)}"`,`"${esc(r.payee_name)}"`,`"${esc(r.bank_code)}"`,`"${esc(r.account_no)}"`].join(',')).join('\n');
  return [hdr,body].join('\n');
}
async function exportCsv(batch_id){
  const q=await db.q(`SELECT advertiser_id,amount,payee_name,bank_code,account_no
                        FROM payout_batch_items
                       WHERE batch_id=$1 ORDER BY amount DESC`,[batch_id]);
  return _csv(q.rows||[]);
}

module.exports={ preview, build, approve, send, exportCsv };

