const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db'); const cbk=require('../lib/chargebacks'); let alertsCh=null; try{ alertsCh=require('../lib/alerts_channels'); }catch(_){ alertsCh=null; }
const fs=require('fs');

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/ledger/cbk/cases', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id = req.query.id? Number(req.query.id) : null;
  if(id){
    const row=(await db.q(`SELECT * FROM chargeback_cases WHERE id=$1`,[id])).rows[0]||null;
    const evs=(await db.q(`SELECT * FROM chargeback_events WHERE case_id=$1 ORDER BY id ASC`,[id])).rows||[];
    const evd=(await db.q(`SELECT id,filename,sha256,kind,bytes,note,created_at FROM chargeback_evidence WHERE case_id=$1 ORDER BY id ASC`,[id])).rows||[];
    return res.json({ ok:true, item: row, events: evs, evidence: evd });
  }
  const rows=(await db.q(`SELECT * FROM chargeback_cases ORDER BY id DESC LIMIT 200`)).rows;
  res.json({ ok:true, items: rows });
});

r.post('/ledger/cbk/open', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { txid=null, advertiser_id=null, amount=0, reason_code=null } = req.body||{};
  const row = await cbk.openCase({ txid, advertiser_id, amount, reason_code, created_by: req.admin?.sub||'admin' });
  if(alertsCh) try{ await alertsCh.notifyWithSeverity('warn','CBK_OPEN',{ id: row.id, txid, advertiser_id, amount }); }catch(_){}
  res.json({ ok:true, id: row.id });
});

r.post('/ledger/cbk/evidence/add', adminCORS||((req,res,n)=>n()), guard, express.json({limit:'5mb'}), async (req,res)=>{
  const { case_id, filename='evidence.txt', kind='other', content_base64='', note=null } = req.body||{};
  const ev = await cbk.addEvidence(Number(case_id), { filename, kind, content_base64, note });
  res.json({ ok:true, evidence_id: ev.id, sha256: ev.sha256, bytes: ev.bytes });
});

r.post('/ledger/cbk/represent', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { case_id } = req.body||{};
  await cbk.represent(Number(case_id), { actor: req.admin?.sub||'admin' });
  if(alertsCh) try{ await alertsCh.notifyWithSeverity('info','CBK_REPRESENT',{ case_id }); }catch(_){}
  res.json({ ok:true });
});

r.post('/ledger/cbk/close', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { case_id, outcome='CANCELED', note=null } = req.body||{};
  const out = await cbk.closeCase(Number(case_id), { outcome, note });
  if(alertsCh) try{ await alertsCh.notifyWithSeverity(outcome==='WIN'?'info':'warn','CBK_CLOSE',{ case_id, outcome }); }catch(_){}
  res.json({ ok:true, outcome, adjustment: out.adjustment||null });
});

r.get('/ledger/cbk/evidence.tgz', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id = Number(req.query.id||'0'); if(!id) return res.status(400).json({ ok:false, code:'ID_REQUIRED' });
  const tgz = await cbk.buildEvidenceTgz(id);
  if(!tgz.ok) return res.status(500).json({ ok:false, code:'ARCHIVE_FAIL' });
  res.setHeader('Content-Type','application/gzip');
  res.setHeader('Content-Disposition',`attachment; filename="cbk_${id}.tgz"`);
  res.end(fs.readFileSync(tgz.path));
});

module.exports=r;

