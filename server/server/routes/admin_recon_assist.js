const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { suggestForDiff }=require('../lib/recon_assist'); const db=require('../lib/db');
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

r.get('/ledger/recon/assist', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const id= parseInt(String(req.query.diff_id||'0'),10); if(!id) return res.status(400).json({ ok:false, code:'DIFF_ID_REQUIRED' });
  const s=await suggestForDiff(id);
  res.json(s);
});

r.post('/ledger/recon/apply-suggest', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { diff_id, txid }=req.body||{}; if(!diff_id||!txid) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  // 간단히 RESOLVED 처리(상세 분개는 운영 절차에 맞춰 확장 가능)
  const rr=await db.q(`UPDATE recon_diffs SET status='RESOLVED', resolved_at=now() WHERE id=$1 RETURNING id`,[diff_id]);
  res.json({ ok:true, resolved_id: rr.rows[0]?.id||null });
});
module.exports=r;

