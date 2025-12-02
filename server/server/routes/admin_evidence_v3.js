const express=require('express');
const admin=require('../mw/admin'); const { execSync }=require('child_process');
const r=express.Router();
r.post('/ads/billing/live/evidence/export/v3', admin.requireAdmin, async (req,res)=>{
  try{
    const out = execSync('bash scripts/generate_live_evidence_v3.sh', { encoding:'utf8' }).trim();
    res.json({ ok:true, file: out });
  }catch(e){ res.status(500).json({ ok:false, code:'EVIDENCE_V3_FAIL', err: String(e.message||e) }); }
});
module.exports=r;
