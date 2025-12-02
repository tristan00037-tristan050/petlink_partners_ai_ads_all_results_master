const express = require('express');
const db = require('../lib/db');
const admin = require('../mw/admin');
const { requireRole } = require('../mw/role');
const r = express.Router();

/** 목록: 고급 필터 지원
 *  GET /admin/advertisers?q=&missing=phone|address&from=&to=&limit=&offset=
 */
r.get('/', admin.requireAdmin, async (req,res)=>{
  const q = (req.query.q||'').toString().trim();
  const missing = (req.query.missing||'').toString().toLowerCase();
  const from = req.query.from ? new Date(String(req.query.from)) : null;
  const to   = req.query.to   ? new Date(String(req.query.to))   : null;
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit||'50',10)));
  const offset = Math.max(0, parseInt(req.query.offset||'0',10));
  const P=[]; let i=1; const W=[];
  if(q){
    if(/^\d+$/.test(q)){ W.push(`ap.advertiser_id = $${i++}`); P.push(parseInt(q,10)); }
    else { W.push(`lower(COALESCE(ap.store_name,ap.name,'')) LIKE $${i++}`); P.push('%'+q.toLowerCase()+'%'); }
  }
  if(missing==='phone'){ W.push(`(ap.phone IS NULL OR ap.phone='')`); }
  if(missing==='address'){ W.push(`(ap.address IS NULL OR ap.address='')`); }
  if(from){ W.push(`ap.updated_at >= $${i++}`); P.push(from); }
  if(to){   W.push(`ap.updated_at <= $${i++}`); P.push(to); }
  const where = W.length? `WHERE ${W.join(' AND ')}`:'';
  const total = await db.q(`SELECT count(*)::int c FROM advertiser_profile ap ${where}`, P);
  const rows  = await db.q(
    `SELECT ap.advertiser_id, COALESCE(ap.store_name,'') AS name, ap.phone, ap.address, ap.updated_at
       FROM advertiser_profile ap
       ${where}
       ORDER BY ap.advertiser_id
       LIMIT ${limit} OFFSET ${offset}`, P);
  res.json({ ok:true, items: rows.rows, total: total.rows[0].c, limit, offset });
});

/** 대량 수정(superadmin 전용) - /:advertiser_id보다 먼저 정의 */
r.put('/bulk', admin.requireAdmin, requireRole('superadmin'), express.json(), async (req,res)=>{
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if(!items.length) return res.status(400).json({ ok:false, code:'EMPTY' });
  await db.transaction(async(c)=>{
    for (const it of items){
      const id = parseInt(String(it.advertiser_id||0),10);
      if(!id || isNaN(id)) continue;
      const cur = await c.query(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
      const before = cur.rows[0] || { advertiser_id:id, name:null, phone:null, address:null };
      await c.query(
        `INSERT INTO advertiser_profile(advertiser_id,store_name,phone,address)
         VALUES($1,$2,$3,$4)
         ON CONFLICT (advertiser_id) DO UPDATE SET
           store_name=COALESCE(EXCLUDED.store_name,advertiser_profile.store_name),
           phone=COALESCE(EXCLUDED.phone,advertiser_profile.phone),
           address=COALESCE(EXCLUDED.address,advertiser_profile.address)`,
        [id, it.name ?? before.name, it.phone ?? before.phone, it.address ?? before.address]
      );
      const after = (await c.query(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id])).rows[0];
      const diff={}; for (const k of ['name','phone','address']) if((before[k]||null)!==(after[k]||null)) diff[k]={before:before[k]||null,after:after[k]||null};
      await c.query(`INSERT INTO admin_audit(actor,entity,entity_id,action,diff) VALUES($1,'advertiser_profile',$2,'BULK_UPDATE',$3::jsonb)`,
                    [String(req.get('X-Admin-Role')||'superadmin'), String(id), JSON.stringify(diff)]);
    }
  });
  res.json({ ok:true, updated: items.length });
});

/** 상세 */
r.get('/:advertiser_id', admin.requireAdmin, async (req,res)=>{
  const id = parseInt(req.params.advertiser_id,10);
  const p = await db.q(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address,updated_at FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
  if(!p.rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  res.json({ ok:true, profile: p.rows[0] });
});

/** 단건 수정(operators 허용) */
r.put('/:advertiser_id', admin.requireAdmin, express.json(), async (req,res)=>{
  const id = parseInt(String(req.params.advertiser_id||0),10);
  if(!id || isNaN(id)) return res.status(400).json({ ok:false, code:'INVALID_ID' });
  const cur = await db.q(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
  const before = cur.rows[0] || { advertiser_id:id, name:null, phone:null, address:null };
  await db.q(
    `INSERT INTO advertiser_profile(advertiser_id,store_name,phone,address)
     VALUES($1,$2,$3,$4)
     ON CONFLICT (advertiser_id) DO UPDATE SET
       store_name=COALESCE(EXCLUDED.store_name,advertiser_profile.store_name),
       phone=COALESCE(EXCLUDED.phone,advertiser_profile.phone),
       address=COALESCE(EXCLUDED.address,advertiser_profile.address)`,
    [id, req.body.name ?? before.name, req.body.phone ?? before.phone, req.body.address ?? before.address]
  );
  const after = (await db.q(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address,updated_at FROM advertiser_profile WHERE advertiser_id=$1`,[id])).rows[0];
  const diff={}; for (const k of ['name','phone','address']) if((before[k]||null)!==(after[k]||null)) diff[k]={before:before[k]||null,after:after[k]||null};
  await db.q(`INSERT INTO admin_audit(actor,entity,entity_id,action,diff) VALUES($1,'advertiser_profile',$2,'UPDATE',$3::jsonb)`,
             [String(req.get('X-Admin-Role')||'admin'), String(id), JSON.stringify(diff)]);
  res.json({ ok:true, profile: after });
});

/** CSV Export: 그대로 유지(최대 1000건) */
r.get('/export.csv', admin.requireAdmin, async (req,res)=>{
  const q = (req.query.q||'').toString().trim();
  const P=[]; let i=1; const W=[];
  if(q){ if(/^\d+$/.test(q)){ W.push(`ap.advertiser_id=$${i++}`); P.push(parseInt(q,10)); }
         else { W.push(`lower(COALESCE(ap.store_name,'')) LIKE $${i++}`); P.push('%'+q.toLowerCase()+'%'); } }
  const where = W.length? `WHERE ${W.join(' AND ')}`:'';
  const rows = await db.q(`SELECT ap.advertiser_id, COALESCE(ap.store_name,'') AS name, COALESCE(ap.phone,'') AS phone, COALESCE(ap.address,'') AS address
                           FROM advertiser_profile ap ${where} ORDER BY ap.advertiser_id LIMIT 1000`, P);
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.setHeader('Content-Disposition','attachment; filename="advertisers.csv"');
  res.write("advertiser_id,name,phone,address\n");
  for (const r of rows.rows){ res.write(`${r.advertiser_id},"${String(r.name).replace(/"/g,'""')}","${String(r.phone).replace(/"/g,'""')}","${String(r.address).replace(/"/g,'""')}"\n`); }
  res.end();
});

module.exports = r;
