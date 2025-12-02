const express=require('express');
let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const db=require('../lib/db');
const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);

// ACK-SLA Gate: 최근 15분 내 미ACK된 flip 이벤트가 없으면 pass
r.get('/reports/pilot/flip/acksla', adminCORS||((req,res,n)=>n()), guard, async (req,res)=>{
  const thrMin=parseInt(process.env.ACK_SLA_MINUTES||'15',10);
  const q=await db.q(`
    SELECT COUNT(*)::int AS unacked_count
    FROM pilot_flip_events
    WHERE flipped_at >= now()-($1||' minutes')::interval
      AND acked IS NOT TRUE
  `,[thrMin]);
  const unacked=q.rows[0]?.unacked_count||0;
  const pass=unacked===0;
  res.json({ ok:true, pass, unacked, threshold_minutes: thrMin });
});

module.exports=r;

