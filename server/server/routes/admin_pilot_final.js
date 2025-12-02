const express=require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db');
const final=require('../lib/pilot_final');
const alertsCh=(function(){ try{ return require('../lib/alerts_channels'); }catch(_){ return null; } })();

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

// 미리보기 JSON
r.get('/reports/pilot/final/preview', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const b=await final.build(); res.json(b);
});

// HTML
r.get('/reports/pilot/final', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const b=await final.build();
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>${b.title}</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2 style="margin:0 0 10px">${b.title}</h2>
    <pre style="white-space:pre-wrap;background:#f8f8f8;padding:12px;border-radius:6px">${b.summary_md.replace(/[&<>]/g,s=>({ '&':'&amp;','<':'&lt;','>':'&gt;'}[s]))}</pre>
  </div>`);
});

// Markdown Export
r.get('/reports/pilot/final.md', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const b=await final.build();
  res.setHeader('Content-Type','text/markdown; charset=utf-8');
  res.end(`# ${b.title}\n\n${b.summary_md}`);
});

// 저장
r.post('/reports/pilot/final/generate', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const b=await final.build();
  const q=await db.q(`INSERT INTO pilot_final_reports(period_start,period_end,title,summary_md,payload)
                      VALUES($1,$2,$3,$4,$5) RETURNING id`,
                      [b.payload.core.period.start, b.payload.core.period.end, b.title, b.summary_md, b.payload]);
  res.json({ ok:true, id:q.rows[0]?.id||null });
});

// 이력 조회
r.get('/reports/pilot/final/history', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const q=await db.q(`SELECT id,period_start,period_end,title,created_at FROM pilot_final_reports ORDER BY id DESC LIMIT 200`);
  res.json({ ok:true, items:q.rows });
});

// 단건 조회
r.get('/reports/pilot/final/:id.json', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id=+req.params.id; if(!id) return res.status(400).json({ ok:false, code:'ID_REQUIRED' });
  const q=await db.q(`SELECT * FROM pilot_final_reports WHERE id=$1`,[id]);
  if(!q.rows[0]) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  res.json({ ok:true, item:q.rows[0] });
});

// Autopush(웹훅)
r.post('/reports/pilot/final/autopush', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const b=await final.build();
  let sent=false;
  try{
    if(alertsCh && typeof alertsCh.notifyWithSeverity==='function'){
      const r=await alertsCh.notifyWithSeverity('info','PILOT_FINAL',{ text: b.summary_md, title: b.title });
      sent=!!r.ok;
    } else {
      console.log('[pilot-final]', b.title); sent=false;
    }
  }catch(_){}
  res.json({ ok:true, sent });
});

module.exports=r;

