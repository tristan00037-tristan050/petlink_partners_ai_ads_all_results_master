const express=require("express"); const { requireAdminAny }=require("../mw/admin_gate"); const r=express.Router();
const LOG=[]; // 메모리 로그(스테이징 전용). 운영은 DB 감사 파이프와 결합.

r.use((req,res,next)=>{ const t0=Date.now(); const end=res.end; res.end=function(...a){ const ms=Date.now()-t0;
  LOG.unshift({ts:new Date().toISOString(), actor:req.admin?.sub||"admin@local", method:req.method, path:req.path, status:res.statusCode, ms}); if(LOG.length>1000) LOG.length=1000; end.apply(this,a); }; next(); });

r.get("/audit/logs", requireAdminAny, (req,res)=>{ const n=Math.min(500,parseInt(req.query.limit||"100",10)); res.json({ok:true,items:LOG.slice(0,n)}); });

r.get("/audit/logs/export.csv", requireAdminAny, (req,res)=>{ res.setHeader("Content-Type","text/csv; charset=utf-8"); res.setHeader("Content-Disposition","attachment; filename=\"audit_logs.csv\"");
  res.write("ts,actor,method,path,status,ms\n"); for(const x of LOG){ res.write([x.ts,x.actor,x.method,x.path,x.status,x.ms].join(",")+"\n"); } res.end(); });

module.exports=r;
