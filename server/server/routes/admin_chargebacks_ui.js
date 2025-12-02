const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const { timeline, addNote, assign, slaBoard }=require('../lib/cbk_timeline');
const { dispatchTicket }=require('../lib/cbk_ticket_webhook');
const db=require('../lib/db');

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

const esc=(s)=>String(s??'').replace(/[&<>]/g, c=>({ '&':'&amp;','<':'&lt;','>':'&gt;' }[c]));

r.get('/ledger/cbk/timeline', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id=parseInt(String(req.query.id||'0'),10); if(!id) return res.status(400).end('id required');
  const tl=await timeline(id); if(!tl.ok) return res.status(404).end('not found');
  const head=tl.case||{};
  const rows=(tl.events||[]).map(e=>`<tr><td>${esc(e.id)}</td><td>${esc(e.kind)}</td><td><pre>${esc(JSON.stringify(e.payload||{},null,2))}</pre></td><td>${esc(e.created_at)}</td></tr>`).join('');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>CBK Timeline #${esc(id)}</title>
  <style>body{font:13px ui-monospace,Menlo,monospace} table{border-collapse:collapse} td,th{border:1px solid #ddd;padding:4px 6px}</style>
  <h3>CBK Case #${esc(id)} — ${esc(head.status)} ${tl.due?.overdue?'<span style="color:#a00">OVERDUE</span>':''}</h3>
  <div>txid: <b>${esc(head.txid)}</b> | advertiser: ${esc(head.advertiser_id)} | amount: ${esc(head.amount)}</div>
  <div>assignee: <b>${esc(head.assignee||'-')}</b> | priority: ${esc(head.priority||'P3')} | due: ${esc(tl.due?.due_at ? (tl.due.due_at instanceof Date ? tl.due.due_at.toISOString() : String(tl.due.due_at)) : '-')}</div>
  <h4>Timeline</h4>
  <table><thead><tr><th>id</th><th>kind</th><th>payload</th><th>created_at</th></tr></thead><tbody>${rows}</tbody></table>`);
});

r.post('/ledger/cbk/note', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { case_id, message }=req.body||{}; if(!case_id) return res.status(400).json({ ok:false, code:'CASE_REQUIRED' });
  const actor=req.admin?.sub||'admin';
  return res.json(await addNote(parseInt(case_id,10), actor, String(message||'')));
});

r.post('/ledger/cbk/assign', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { case_id, assignee }=req.body||{}; if(!case_id || !assignee) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  return res.json(await assign(parseInt(case_id,10), String(assignee)));
});

r.get('/ledger/cbk/sla/board.json', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  return res.json(await slaBoard());
});

r.get('/ledger/cbk/sla/board', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  const b=await slaBoard(); const rows=(b.items||[]).map(x=>`<tr>
    <td>${esc(x.id)}</td><td>${esc(x.txid)}</td><td>${esc(x.advertiser_id)}</td>
    <td>${esc(x.amount)}</td><td>${esc(x.status)}</td>
    <td>${esc(x.assignee||'-')}</td><td>${esc(x.priority||'P3')}</td>
    <td>${esc(x.due_at)}</td><td style="color:${x.overdue?'#a00':'#0a5'}">${esc(x.due_days)}</td>
  </tr>`).join('');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>CBK SLA Board</title>
  <style>table{border-collapse:collapse;font:13px ui-monospace,Menlo,monospace}td,th{border:1px solid #ddd;padding:4px 6px}</style>
  <h3>CBK SLA Board (D=${esc(String(process.env.CBK_SLA_DAYS||'7'))})</h3>
  <table><thead><tr><th>case_id</th><th>txid</th><th>advertiser</th><th>amount</th><th>status</th><th>assignee</th><th>priority</th><th>due_at</th><th>due_days</th></tr></thead><tbody>${rows}</tbody></table>`);
});

r.post('/ledger/cbk/ticket/webhook', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { case_id }=req.body||{}; if(!case_id) return res.status(400).json({ ok:false, code:'CASE_REQUIRED' });
  // 최소 payload(외부 시스템 자유형)
  const c=(await db.q(`SELECT * FROM chargeback_cases WHERE id=$1`,[case_id])).rows[0]||{};
  const payload={ case_id, txid:c.txid, advertiser_id:c.advertiser_id, amount:c.amount, status:c.status, assignee:c.assignee, priority:c.priority };
  return res.json(await dispatchTicket(parseInt(case_id,10), payload));
});

r.get('/ledger/cbk/export2.csv', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period=String(req.query.period||'').trim(); if(!period) return res.status(400).end('period required');
  // 기간 내(YYYY-MM) 케이스를 기준 CSV
  const rows=(await db.q(`
      SELECT id AS case_id, txid, advertiser_id, amount, status, outcome, assignee, priority, due_at, opened_at
        FROM chargeback_cases
       WHERE to_char(opened_at,'YYYY-MM')=$1
       ORDER BY id ASC`, [period])).rows || [];
  const esc=(s)=>String(s??'').replace(/"/g,'""');
  const csv=['case_id,txid,advertiser_id,amount,status,outcome,assignee,priority,due_at,opened_at']
    .concat(rows.map(x=>[x.case_id,x.txid,x.advertiser_id,x.amount,x.status,x.outcome||'',x.assignee||'',x.priority||'P3',x.due_at||'',x.opened_at||''].map(esc).map(v=>`"${v}"`).join(',')))
    .join('\n');
  res.setHeader('Content-Type','text/csv; charset=utf-8'); res.end(csv);
});

module.exports=r;

