const express=require('express'); const path=require('path'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
r.get('/prod/live/subs/ui', adminCORS||((req,res,n)=>n()), guard, (_req,res)=>{
  res.sendFile(path.join(__dirname,'..','public','admin-ui','subs-policy.html'));
});
module.exports=r;

