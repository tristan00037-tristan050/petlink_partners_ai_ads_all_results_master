const db=require('../lib/db');

const SLA_DAYS=parseInt(process.env.CBK_SLA_DAYS||'7',10);

async function loadCase(case_id){
  const q=await db.q(`SELECT * FROM chargeback_cases WHERE id=$1`,[case_id]);
  return q.rows[0]||null;
}
async function loadEvents(case_id){
  const q=await db.q(`SELECT id,kind,payload,created_at FROM chargeback_events WHERE case_id=$1 ORDER BY id ASC`,[case_id]);
  return q.rows||[];
}
async function computeDue(c){
  if(!c) return { due_at:null, due_days:null, overdue:false };
  let dueAt=c.due_at;
  if(!dueAt){
    // created_at 또는 opened_at 유사 컬럼 추정
    const qq=await db.q(`SELECT created_at FROM chargeback_events WHERE case_id=$1 ORDER BY id ASC LIMIT 1`,[c.id]);
    const openedAt=qq.rows[0]?.created_at || c.created_at || new Date();
    dueAt=new Date(new Date(openedAt).getTime()+SLA_DAYS*24*60*60*1000);
  }
  const now=new Date();
  const days=Math.ceil((dueAt-now)/ (24*60*60*1000));
  return { due_at: dueAt, due_days: days, overdue: days<0 };
}

async function timeline(case_id){
  const c=await loadCase(case_id);
  if(!c) return { ok:false, code:'NOT_FOUND' };
  const ev=await loadEvents(case_id);
  const due=await computeDue(c);
  return { ok:true, case:c, events:ev, due, sla_days:SLA_DAYS };
}

async function addNote(case_id, actor, message){
  await db.q(`INSERT INTO chargeback_events(case_id, kind, payload, created_at)
              VALUES($1,'NOTE',$2,now())`,[case_id,{ actor, message }]);
  return { ok:true };
}
async function assign(case_id, assignee){
  await db.q(`UPDATE chargeback_cases SET assignee=$2 WHERE id=$1`,[case_id, assignee]);
  await db.q(`INSERT INTO chargeback_events(case_id, kind, payload, created_at)
              VALUES($1,'ASSIGN',$2,now())`,[case_id,{ assignee }]);
  return { ok:true };
}

async function slaBoard(){
  // OPEN/REPRESENTED 상태의 케이스를 마감되지 않은 것으로 간주
  const rows=(await db.q(`SELECT c.*, 
     COALESCE(c.due_at, (SELECT created_at FROM chargeback_events e WHERE e.case_id=c.id ORDER BY id ASC LIMIT 1) + ($1||' days')::interval) AS calc_due_at
    FROM chargeback_cases c
    WHERE c.status IN ('OPEN','REPRESENTED') 
    ORDER BY calc_due_at ASC, id ASC`, [String(SLA_DAYS)])).rows;
  const now=new Date();
  const items=rows.map(r=>{
    const dueAt=r.calc_due_at||r.due_at||new Date();
    const days=Math.ceil((dueAt-now)/ (24*60*60*1000));
    return { id:r.id, txid:r.txid, advertiser_id:r.advertiser_id, amount:r.amount, status:r.status,
             assignee:r.assignee, priority:r.priority, due_at:dueAt, due_days:days, overdue:(days<0) };
  });
  return { ok:true, items };
}

module.exports={ timeline, addNote, assign, slaBoard };

