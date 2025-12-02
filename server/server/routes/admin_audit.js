const express = require("express");
const db = require("../lib/db");
const admin = require("../mw/admin");
const r = express.Router();

r.get("/logs", admin.requireAdmin, async (req,res)=>{
  const { from, to, actor_type, advertiser_id, limit="50" } = req.query;
  const P=[]; let i=1; const W=[];
  if(actor_type){ W.push(`actor_type=$${i++}`); P.push(actor_type); }
  if(advertiser_id){ W.push(`advertiser_id=$${i++}`); P.push(Number(advertiser_id)); }
  if(from){ W.push(`ts>=$${i++}`); P.push(new Date(from)); }
  if(to){ W.push(`ts<=$${i++}`); P.push(new Date(to)); }
  const where = W.length? ("WHERE "+W.join(" AND ")) : "";
  const rows = (await db.q(`SELECT id,ts,actor_type,actor_id,advertiser_id,method,path,status,req_id,ip,meta
                             FROM audit_logs ${where} ORDER BY id DESC LIMIT ${parseInt(limit,10)}`, P)).rows;
  res.json({ ok:true, items: rows });
});

module.exports = r;
