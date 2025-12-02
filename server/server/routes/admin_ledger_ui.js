const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const db=require('../lib/db'); const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
function parsePeriod(p){ if(!p) return null; const m=/^(\d{4})-(\d{2})$/.exec(p); if(!m) return null; return { y:+m[1], m:+m[2] }; }

r.get('/ledger/ui', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const period=parsePeriod(String(req.query.period||'')); const aid= req.query.advertiser_id? +req.query.advertiser_id : null; const kind= req.query.kind||null;
  const params=[]; let where='1=1';
  if(period){ params.push(`${period.y}-${String(period.m).padStart(2,'0')}-01`); where+=` AND event_at >= $${params.length}::date AND event_at < ($${params.length}::date + interval '1 month')`; }
  if(aid){ params.push(aid); where+=` AND COALESCE(advertiser_id,0)=$${params.length}`; }
  if(kind){ params.push(kind); where+=` AND COALESCE(kind,'')=$${params.length}`; }
  const q=await db.q(`SELECT event_at AS created_at, txid, advertiser_id, amount, kind, status FROM live_ledger WHERE ${where} ORDER BY event_at DESC LIMIT 200`, params);
  const rows=q.rows||[];
  const esc=(s)=>String(s??'').replace(/[&<>]/g,c=>({ '&':'&amp;','<':'&lt;','>':'&gt;' }[c]));
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Ledger UI</title>
  <div style="font:14px system-ui,Arial;padding:16px">
   <h2 style="margin:0 0 8px">Ledger Entries</h2>
   <div style="margin-bottom:8px;color:#666">Filters: period(YYYY-MM), advertiser_id, kind</div>
   <table border="1" cellspacing="0" cellpadding="6"><tr><th>created_at</th><th>txid</th><th>adv</th><th>amount</th><th>kind</th><th>status</th></tr>
    ${rows.map(r=>`<tr><td>${esc(r.created_at)}</td><td>${esc(r.txid)}</td><td>${esc(r.advertiser_id)}</td><td>${esc(r.amount)}</td><td>${esc(r.kind)}</td><td>${esc(r.status)}</td></tr>`).join('')}
   </table>
  </div>`);
});

r.get('/ledger/evidence/view', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const tx=String(req.query.txid||'');
  const ev=(await db.q(`SELECT * FROM ci_evidence WHERE COALESCE(txid, ledger_txid)=$1`,[tx])).rows[0]||null;
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Evidence</title>
  <pre style="font:13px ui-monospace,Menlo,monospace;white-space:pre-wrap">${ev?JSON.stringify(ev,null,2):'No evidence'}</pre>`);
});
module.exports=r;

