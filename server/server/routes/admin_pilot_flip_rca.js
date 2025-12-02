const express=require('express');
const db=require('../lib/db');
const { compute }=require('../lib/flip_cause');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

// 최신 이벤트 1건 조회
async function latestEvent(){
  const q=await db.q(`SELECT * FROM pilot_flip_events ORDER BY flipped_at DESC LIMIT 1`);
  return q.rows[0]||null;
}

// 원인분석 API
r.get('/reports/pilot/flip/causes', adminCORS||((req,res,next)=>next()), guard, async (req,res)=>{
  try{
    const row = (req.query.latest==='1'||req.query.latest==='true') ? (await latestEvent()) : null;
    const id  = row?.id || (req.query.id ? Number(req.query.id) : null);
    let ev = row;
    if(!ev && id){ ev = (await db.q(`SELECT * FROM pilot_flip_events WHERE id=$1 LIMIT 1`,[id])).rows[0]; }
    if(!ev){ return res.json({ ok:false, code:'NO_EVENT' }); }
    const c = await compute();
    await db.q(`UPDATE pilot_flip_events SET cause_tags=$1, cause_summary=$2 WHERE id=$3`,[c.tags, c.summary, ev.id]);
    res.json({ ok:true, id: ev.id, cause: c });
  }catch(e){ res.status(500).json({ ok:false, code:'RCA_ERROR', err:String(e?.message||e) }); }
});

// 룰 조회/적용
r.get('/reports/pilot/flip/rules', adminCORS||((req,res,next)=>next()), guard, async (_req,res)=>{
  const q=await db.q(`SELECT id,name,active,params,updated_at FROM pilot_flip_rules ORDER BY id`);
  res.json({ ok:true, items:q.rows });
});
r.post('/reports/pilot/flip/rules/apply', adminCORS||((req,res,next)=>next()), guard, express.json(), async (req,res)=>{
  const items = Array.isArray(req.body?.items)? req.body.items : [];
  for(const it of items){
    await db.q(`
      INSERT INTO pilot_flip_rules(name,active,params) VALUES($1,$2,$3)
      ON CONFLICT (name) DO UPDATE SET active=EXCLUDED.active, params=EXCLUDED.params, updated_at=now()
    `,[it.name, !!it.active, it.params||{}]);
  }
  const q=await db.q(`SELECT id,name,active,params FROM pilot_flip_rules ORDER BY id`);
  res.json({ ok:true, items:q.rows });
});

// ACK(메타 포함) — 기존 경로와 동일 prefix
r.post('/reports/pilot/flip/ack', adminCORS||((req,res,next)=>next()), guard, express.json(), async (req,res)=>{
  try{
    const ids = Array.isArray(req.body?.ids)? req.body.ids : [];
    const reason = String(req.body?.reason||'acknowledged');
    const note   = String(req.body?.note||'');
    const who    = String(req.admin?.sub || 'admin@local');
    if(ids.length===0) return res.status(400).json({ ok:false, code:'IDS_REQUIRED' });
    await db.q(`UPDATE pilot_flip_events SET acked=TRUE, ack_by=$1, ack_reason=$2, ack_note=$3, ack_at=now() WHERE id = ANY($4::bigint[])`,[who, reason, note, ids]);
    res.json({ ok:true, updated: ids.length });
  }catch(e){ res.status(500).json({ ok:false, code:'ACK_ERROR', err:String(e?.message||e) }); }
});

// 소거(서프레션) 시뮬 + INSERT (watcher에 영향 없이 테스트용)
r.post('/reports/pilot/flip/simulate2', adminCORS||((req,res,next)=>next()), guard, express.json(), async (req,res)=>{
  try{
    const to = String(req.body?.to||'hold').toLowerCase()==='go';
    const prev = !to;
    const c = await compute();
    // 룰 조회
    const rls = (await db.q(`SELECT name,active,params FROM pilot_flip_rules WHERE active=TRUE`)).rows;
    let suppress=false;
    const sameCauseMin = Number((rls.find(x=>x.name==='suppress_same_cause_minutes')?.params||{}).minutes||30);
    const since = await db.q(`SELECT * FROM pilot_flip_events WHERE flipped_at>=now()-($1||' minutes')::interval ORDER BY flipped_at DESC`,[sameCauseMin]);
    for(const e of since.rows){
      if(Array.isArray(e.cause_tags) && e.cause_tags.join(',')===c.tags.join(',')){ suppress=true; break; }
    }
    const ins = await db.q(`INSERT INTO pilot_flip_events(prev_go,next_go,flipped_at,source,payload,acked,suppressed,cause_tags,cause_summary)
                            VALUES($1,$2,now(),'simulate2',$3,false,$4,$5,$6) RETURNING id`,
                            [prev,to, {rca:c}, suppress, c.tags, c.summary]);
    res.json({ ok:true, id: ins.rows[0].id, suppressed: suppress, cause: c });
  }catch(e){ res.status(500).json({ ok:false, code:'SIM_FAIL', err:String(e?.message||e) }); }
});

// RCA/ACK 간단 HTML
r.get('/reports/pilot/flip/ui', adminCORS||((req,res,next)=>next()), guard, async (_req,res)=>{
  const ev=(await db.q(`SELECT id,prev_go,next_go,flipped_at,acked,suppressed,cause_tags,cause_summary FROM pilot_flip_events ORDER BY flipped_at DESC LIMIT 200`)).rows;
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Pilot Flip RCA</title>
  <div style="font:14px system-ui,Arial;padding:16px;max-width:980px;margin:0 auto">
    <h2 style="margin:0 0 10px">Flip RCA / ACK</h2>
    <div style="margin:10px 0">
      <button id="btn-rule-apply">Apply Default Rules</button>
      <button id="btn-sim-hold">Simulate HOLD</button>
      <button id="btn-sim-go">Simulate GO</button>
    </div>
    <table border="1" cellpadding="6" cellspacing="0" style="width:100%">
      <thead><tr><th>sel</th><th>id</th><th>time</th><th>flip</th><th>suppressed</th><th>acked</th><th>cause</th></tr></thead>
      <tbody>
        ${ev.map(x=>`<tr>
          <td><input type="checkbox" value="${x.id}"></td>
          <td>${x.id}</td>
          <td>${x.flipped_at}</td>
          <td>${x.prev_go?'GO':'HOLD'} → ${x.next_go?'GO':'HOLD'}</td>
          <td>${x.suppressed?'yes':'no'}</td>
          <td>${x.acked?'yes':'no'}</td>
          <td>${(x.cause_tags||[]).join(',')||x.cause_summary||''}</td>
        </tr>`).join('')}
      </tbody>
    </table>
    <div style="margin-top:8px">
      <select id="ack-reason">
        <option value="acknowledged">acknowledged</option>
        <option value="maintenance_window">maintenance_window</option>
        <option value="threshold_tuning">threshold_tuning</option>
        <option value="false_positive">false_positive</option>
        <option value="incident_opened">incident_opened</option>
      </select>
      <input id="ack-note" placeholder="note" style="width:240px">
      <button id="btn-ack">ACK Selected</button>
    </div>
  </div>
  <script>
    const H={'X-Admin-Key':'${process.env.ADMIN_KEY||''}','Content-Type':'application/json'};
    function sel(){ return [...document.querySelectorAll('tbody input[type=checkbox]:checked')].map(x=>Number(x.value)); }
    document.getElementById('btn-ack').onclick=async()=>{
      const ids=sel(); if(ids.length===0){ alert('select'); return; }
      const body={ ids, reason: document.getElementById('ack-reason').value, note: document.getElementById('ack-note').value };
      const j=await (await fetch('/admin/reports/pilot/flip/ack',{method:'POST',headers:H,body:JSON.stringify(body)})).json();
      alert('ack: '+JSON.stringify(j)); location.reload();
    };
    document.getElementById('btn-rule-apply').onclick=async()=>{
      const items=[
        {name:'suppress_same_cause_minutes',active:true,params:{minutes:30}},
        {name:'business_hours_only',active:true,params:{tz:'Asia/Seoul',start:'09:00',end:'21:00'}}
      ];
      const j=await (await fetch('/admin/reports/pilot/flip/rules/apply',{method:'POST',headers:H,body:JSON.stringify({items})})).json();
      alert('rules: '+JSON.stringify(j));
    };
    document.getElementById('btn-sim-hold').onclick=async()=>{
      const j=await (await fetch('/admin/reports/pilot/flip/simulate2',{method:'POST',headers:H,body:JSON.stringify({to:'hold'})})).json();
      alert('sim hold: '+JSON.stringify(j)); location.reload();
    };
    document.getElementById('btn-sim-go').onclick=async()=>{
      const j=await (await fetch('/admin/reports/pilot/flip/simulate2',{method:'POST',headers:H,body:JSON.stringify({to:'go'})})).json();
      alert('sim go: '+JSON.stringify(j)); location.reload();
    };
  </script>`);
});

module.exports=r;

