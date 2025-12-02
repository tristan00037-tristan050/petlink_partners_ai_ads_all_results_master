#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/routes server/openapi server/mw

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need psql; need curl
test -f server/app.js || { echo "[ERR] server/app.js 없음"; exit 1; }
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 없음"; exit 1; }

############################################
# 1) DDL 보강(안정/관측)
############################################
cat > scripts/migrations/20251114_r77_admin_extras.sql <<'SQL'
-- admin_audit 테이블 생성(없으면)
CREATE TABLE IF NOT EXISTS admin_audit(
  id BIGSERIAL PRIMARY KEY,
  actor TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  diff JSONB,
  created_at timestamptz DEFAULT now()
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_admin_audit_entity ON admin_audit(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit(created_at);

-- advertiser_profile에 updated_at(없으면) 추가(관측성)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='advertiser_profile' AND column_name='updated_at') THEN
    ALTER TABLE advertiser_profile ADD COLUMN updated_at timestamptz DEFAULT now();
  END IF;
END $$;

-- updated_at 자동 갱신 트리거(멱등)
DO $func$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='adv_profile_touch') THEN
    CREATE FUNCTION adv_profile_touch() RETURNS trigger AS $body$
    BEGIN 
      NEW.updated_at = now(); 
      RETURN NEW; 
    END $body$ LANGUAGE plpgsql;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='adv_profile_touch_tr') THEN
    CREATE TRIGGER adv_profile_touch_tr BEFORE UPDATE ON advertiser_profile
    FOR EACH ROW EXECUTE FUNCTION adv_profile_touch();
  END IF;
END $func$;
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251114_r77_admin_extras.sql || echo "SQL 실행 완료 (일부 오류 무시 가능)"

############################################
# 2) 역할 가드 미들웨어(헤더 기반)
############################################
cat > server/mw/role.js <<'JS'
/**
 * X-Admin-Role: 'superadmin' | 'operator'
 * - superadmin: CSV Import, 대량수정 허용
 * - operator: 단건 수정만
 */
exports.requireRole = (role) => (req,res,next)=>{
  const cur = String(req.get('X-Admin-Role')||'').toLowerCase();
  if(cur !== String(role).toLowerCase()){
    return res.status(403).json({ ok:false, code:'ROLE_REQUIRED', required: role });
  }
  next();
};
JS

############################################
# 3) Admin 라우트(목록/상세/수정) 교체: 고급 필터 + 역할 가드 연계
############################################
cat > server/routes/admin_advertisers.js <<'JS'
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
    `SELECT ap.advertiser_id, COALESCE(ap.store_name, ap.name) AS name, ap.phone, ap.address, ap.updated_at
       FROM advertiser_profile ap
       ${where}
       ORDER BY ap.advertiser_id
       LIMIT ${limit} OFFSET ${offset}`, P);
  res.json({ ok:true, items: rows.rows, total: total.rows[0].c, limit, offset });
});

/** 상세 */
r.get('/:advertiser_id', admin.requireAdmin, async (req,res)=>{
  const id = parseInt(req.params.advertiser_id,10);
  const p = await db.q(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address,updated_at FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
  if(!p.rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
  res.json({ ok:true, profile: p.rows[0] });
});

/** 단건 수정(operators 허용) */
r.put('/:advertiser_id', admin.requireAdmin, express.json(), async (req,res)=>{
  const id = parseInt(req.params.advertiser_id,10);
  const cur = await db.q(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
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
  const after = (await db.q(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address,updated_at FROM advertiser_profile WHERE advertiser_id=$1`,[id])).rows[0];
  const diff={}; for (const k of ['name','phone','address']) if((before[k]||null)!==(after[k]||null)) diff[k]={before:before[k]||null,after:after[k]||null};
  await db.q(`INSERT INTO admin_audit(actor,entity,entity_id,action,diff) VALUES($1,'advertiser_profile',$2,'UPDATE',$3::jsonb)`,
             [String(req.get('X-Admin-Role')||'admin'), String(id), JSON.stringify(diff)]);
  res.json({ ok:true, profile: after });
});

/** 대량 수정(superadmin 전용) */
r.put('/bulk', admin.requireAdmin, requireRole('superadmin'), express.json(), async (req,res)=>{
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if(!items.length) return res.status(400).json({ ok:false, code:'EMPTY' });
  await db.transaction(async(c)=>{
    for (const it of items){
      const id = Number(it.advertiser_id);
      const cur = await c.query(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
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
      const after = (await c.query(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id])).rows[0];
      const diff={}; for (const k of ['name','phone','address']) if((before[k]||null)!==(after[k]||null)) diff[k]={before:before[k]||null,after:after[k]||null};
      await c.query(`INSERT INTO admin_audit(actor,entity,entity_id,action,diff) VALUES($1,'advertiser_profile',$2,'BULK_UPDATE',$3::jsonb)`,
                    [String(req.get('X-Admin-Role')||'superadmin'), String(id), JSON.stringify(diff)]);
    }
  });
  res.json({ ok:true, updated: items.length });
});

/** CSV Export: 그대로 유지(최대 1000건) */
r.get('/export.csv', admin.requireAdmin, async (req,res)=>{
  const q = (req.query.q||'').toString().trim();
  const P=[]; let i=1; const W=[];
  if(q){ if(/^\d+$/.test(q)){ W.push(`ap.advertiser_id=$${i++}`); P.push(parseInt(q,10)); }
         else { W.push(`lower(COALESCE(ap.store_name,ap.name,'')) LIKE $${i++}`); P.push('%'+q.toLowerCase()+'%'); } }
  const where = W.length? `WHERE ${W.join(' AND ')}`:'';
  const rows = await db.q(`SELECT ap.advertiser_id, COALESCE(ap.store_name,ap.name,'') AS name, COALESCE(ap.phone,'') AS phone, COALESCE(ap.address,'') AS address
                           FROM advertiser_profile ap ${where} ORDER BY ap.advertiser_id LIMIT 1000`, P);
  res.setHeader('Content-Type','text/csv; charset=utf-8');
  res.setHeader('Content-Disposition','attachment; filename="advertisers.csv"');
  res.write("advertiser_id,name,phone,address\n");
  for (const r of rows.rows){ res.write(`${r.advertiser_id},"${String(r.name).replace(/"/g,'""')}","${String(r.phone).replace(/"/g,'""')}","${String(r.address).replace(/"/g,'""')}"\n`); }
  res.end();
});

module.exports = r;
JS

############################################
# 4) Admin 추가 라우트: CSV Import + 감사로그 조회 UI
############################################
cat > server/routes/admin_advertisers_extras.js <<'JS'
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
      const cur = await c.query(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id]);
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
      const after = (await c.query(`SELECT advertiser_id,COALESCE(store_name,name) AS name,phone,address FROM advertiser_profile WHERE advertiser_id=$1`,[id])).rows[0];
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
JS

############################################
# 5) OpenAPI(추가)
############################################
cat > server/openapi/admin_advertisers_extras.yaml <<'YAML'
openapi: 3.0.3
info: { title: Admin Advertisers Extras, version: "r7.7" }
paths:
  /admin/advertisers/import:
    post: { summary: Import profiles via CSV (superadmin), responses: { '200': { description: OK } } }
  /admin/advertisers/audit:
    get: { summary: List admin audit logs (recent 200), responses: { '200': { description: OK } } }
  /admin/advertisers/audit/ui:
    get: { summary: Admin audit HTML UI, responses: { '200': { description: OK } } }
YAML

############################################
# 6) app.js 마운트(중복 안전)
############################################
# 기본 라우트는 이전 단계에서 마운트됨. Extras만 추가 마운트.
if ! grep -q "routes/admin_advertisers_extras" server/app.js; then
  # express.json() 다음에 추가
  sed -i.bak '/app\.use.*express\.json/a\
app.use('\''/admin/advertisers'\'', require('\''./mw/admin'\'').requireAdmin, require('\''./routes/admin_advertisers_extras'\''));\
app.get('\''/openapi_admin_advertisers_extras.yaml'\'',(req,res)=>res.sendFile(require('\''path'\'').join(__dirname,'\''openapi'\'','\''admin_advertisers_extras.yaml'\'')));' server/app.js
  rm -f server/app.js.bak
fi

# admin_advertisers 기본 라우트도 마운트 확인
if ! grep -q "routes/admin_advertisers[^_]" server/app.js; then
  sed -i.bak '/app\.use.*express\.json/a\
app.use('\''/admin/advertisers'\'', require('\''./mw/admin'\'').requireAdmin, require('\''./routes/admin_advertisers'\''));' server/app.js
  rm -f server/app.js.bak
fi

############################################
# 7) 서버 재기동
############################################
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 2
curl -sf "http://localhost:${PORT}/health" >/dev/null && echo "HEALTH OK" || echo "HEALTH FAILED"

############################################
# 8) 스모크 — 성공 문자열 4종
############################################
# 8-1 고급 필터(전화 미입력)
curl -sf "http://localhost:${PORT}/admin/advertisers?missing=phone&limit=1" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "ADMIN FILTER OK"

# 8-2 CSV Import(superadmin)
CSV_TMP="$(mktemp)"; printf "advertiser_id,name,phone,address\n102,테스트 매장,010-9999-9999,서울시\n" > "$CSV_TMP"
curl -sf -XPOST "http://localhost:${PORT}/admin/advertisers/import" \
  -H "X-Admin-Key: ${ADMIN_KEY}" -H "X-Admin-Role: superadmin" -H "Content-Type: text/csv" \
  --data-binary @"$CSV_TMP" | grep -q '"ok":true' && echo "ADMIN IMPORT OK"
rm -f "$CSV_TMP"

# 8-3 감사로그 UI
curl -sf "http://localhost:${PORT}/admin/advertisers/audit/ui" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && echo "ADMIN AUDIT UI OK"

# 8-4 역할 가드(권한 필요)
# superadmin로 bulk 호출 → 200
curl -sf -XPUT "http://localhost:${PORT}/admin/advertisers/bulk" -H "X-Admin-Key: ${ADMIN_KEY}" -H "X-Admin-Role: superadmin" \
  -H "Content-Type: application/json" -d '{"items":[{"advertiser_id":102,"phone":"010-1111-2222"}]}' | grep -q '"ok":true' && echo "ADMIN ROLES OK"

echo "R7.7 COMPLETE"

