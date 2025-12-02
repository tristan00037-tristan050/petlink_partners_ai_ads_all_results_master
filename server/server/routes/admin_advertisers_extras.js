const express = require('express');
const db = require('../lib/db');
const admin = require('../mw/admin');
const { requireRole } = require('../mw/role');
const r = express.Router();

/** CSV Import(superadmin 전용)
 *  헤더: advertiser_id,name,phone,address
 *  Content-Type: text/csv
 */
r.post('/import', admin.requireAdmin, requireRole('superadmin'), express.text({ type: 'text/*', limit: '2mb' }), async (req,res)=>{
  const text = (req.body||'').replace(/\r\n/g,'\n').replace(/\r/g,'\n');
  const lines = text.split('\n').filter(Boolean);
  if(!lines.length) return res.status(400).json({ ok:false, code:'EMPTY_CSV' });
  const header = lines.shift().trim().toLowerCase();
  if(header.replace(/\s/g,'')!=='advertiser_id,name,phone,address') return res.status(400).json({ ok:false, code:'BAD_HEADER' });

  let count=0;
  await db.transaction(async(c)=>{
    for (const ln of lines){
      const cols = ln.split(','); // 주소에 쉼표가 들어오지 않도록 Export 단계에서 정규화한 포맷 기준
      const id = Number(cols[0]||0); if(!id) continue;
      const name = (cols[1]||'').replace(/^"|"$/g,'');
      const phone = (cols[2]||'').replace(/^"|"$/g,'');
      const address = (cols[3]||'').replace(/^"|"$/g,'');
      const cur = await c.query(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
      const before = cur.rows[0] || { advertiser_id:id, name:null, phone:null, address:null };
      await c.query(
        `INSERT INTO advertiser_profile(advertiser_id,store_name,phone,address)
         VALUES($1,$2,$3,$4)
         ON CONFLICT (advertiser_id) DO UPDATE SET
           store_name=COALESCE(EXCLUDED.store_name,advertiser_profile.store_name),
           phone=COALESCE(EXCLUDED.phone,advertiser_profile.phone),
           address=COALESCE(EXCLUDED.address,advertiser_profile.address)`,
        [id, name||before.name, phone||before.phone, address||before.address]
      );
      const after = (await c.query(`SELECT advertiser_id,COALESCE(store_name,'') AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id])).rows[0];
      const diff={}; for (const k of ['name','phone','address']) if((before[k]||null)!==(after[k]||null)) diff[k]={before:before[k]||null,after:after[k]||null};
      await c.query(`INSERT INTO admin_audit(actor,entity,entity_id,action,diff) VALUES($1,'advertiser_profile',$2,'IMPORT_CSV',$3::jsonb)`,
                    [String(req.get('X-Admin-Role')||'superadmin'), String(id), JSON.stringify(diff)]);
      count++;
    }
  });
  res.json({ ok:true, imported: count });
});

/** 감사로그 JSON/최근 200 */
r.get('/audit', admin.requireAdmin, async (req,res)=>{
  const rows = await db.q(`SELECT id,actor,entity,entity_id,action,diff,created_at
                           FROM admin_audit ORDER BY id DESC LIMIT 200`);
  res.json({ ok:true, items: rows.rows });
});

/** 감사로그 UI */
r.get('/audit/ui', admin.requireAdmin, async (req,res)=>{
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Admin Audit</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2>감사 로그(최근 200)</h2>
    <table border="1" cellspacing="0" cellpadding="6">
      <thead><tr><th>ID</th><th>ACTOR</th><th>ENTITY</th><th>ENTITY_ID</th><th>ACTION</th><th>DIFF</th><th>TS</th></tr></thead>
      <tbody id="tb"></tbody>
    </table>
    <script>
      (async()=>{
        const r = await fetch('/admin/advertisers/audit',{headers:{'X-Admin-Key':'${process.env.ADMIN_KEY||''}'}});
        const j = await r.json(); const tb=document.getElementById('tb');
        for(const it of j.items){
          const tr=document.createElement('tr');
          tr.innerHTML=\`<td>\${it.id}</td><td>\${it.actor}</td><td>\${it.entity}</td><td>\${it.entity_id}</td>
                        <td>\${it.action}</td><td><pre style="margin:0">\${JSON.stringify(it.diff,null,2)}</pre></td><td>\${it.created_at}</td>\`;
          tb.appendChild(tr);
        }
      })();
    </script>
  </div>`);
});

module.exports = r;
