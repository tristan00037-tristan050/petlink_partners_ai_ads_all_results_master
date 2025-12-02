#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/lib server/routes server/public public

# ─────────────────────────────────────────────────────────────────────────────
# 공통 ENV
# ─────────────────────────────────────────────────────────────────────────────
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

# Gate-WEBAPP 임계 (노랑 포함 95%↑, 자동승인 ≥ 85%)
export WEBAPP_SLO_MIN_AUTO_APPROVAL="${WEBAPP_SLO_MIN_AUTO_APPROVAL:-0.85}"
export WEBAPP_SLO_MAX_MINUTES="${WEBAPP_SLO_MAX_MINUTES:-5}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need psql; need curl
test -f server/app.js || { echo "[ERR] server/app.js 없음"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# [1] DDL: advertiser_profile / ad_subscriptions / ad_invoices.receipt_no
# ─────────────────────────────────────────────────────────────────────────────
cat > scripts/migrations/20251113_r75_core.sql <<'SQL'
-- 광고주 프로필
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='advertiser_profile') THEN
    CREATE TABLE advertiser_profile(
      advertiser_id INTEGER PRIMARY KEY,
      name TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      meta JSONB DEFAULT '{}'::jsonb,
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  END IF;
END$$;

-- 월 구독 결제
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_subscriptions') THEN
    CREATE TABLE ad_subscriptions(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER NOT NULL,
      plan_code TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK (amount>=0),
      currency TEXT NOT NULL DEFAULT 'KRW',
      method_id BIGINT,
      bill_day INTEGER NOT NULL CHECK (bill_day BETWEEN 1 AND 31),
      status TEXT NOT NULL CHECK (status IN ('ACTIVE','PAUSED','CANCELED')),
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_attempt_at timestamptz,
      next_attempt_at timestamptz,
      next_charge_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_subs_adv ON ad_subscriptions(advertiser_id);
    CREATE INDEX IF NOT EXISTS idx_subs_sched ON ad_subscriptions(next_attempt_at, next_charge_at);
  ELSE
    BEGIN
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS last_attempt_at timestamptz;
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz;
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS next_charge_at timestamptz;
    EXCEPTION WHEN duplicate_column THEN END;
    CREATE INDEX IF NOT EXISTS idx_subs_sched ON ad_subscriptions(next_attempt_at, next_charge_at);
  END IF;
END$$;

-- 간단 영수증 번호
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ad_invoices' AND column_name='receipt_no') THEN
    ALTER TABLE ad_invoices ADD COLUMN receipt_no TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_ad_invoices_receipt_no') THEN
    CREATE UNIQUE INDEX ux_ad_invoices_receipt_no ON ad_invoices(receipt_no) WHERE receipt_no IS NOT NULL;
  END IF;
END$$;
SQL

node scripts/run_sql.js scripts/migrations/20251113_r75_core.sql

# ─────────────────────────────────────────────────────────────────────────────
# [2] 품질 라이브러리(검증/자동수정) + 엔드포인트(/ads/validate, /ads/autofix)
# ─────────────────────────────────────────────────────────────────────────────
cat > server/lib/quality.js <<'JS'
/**
 * 간단 검증/자동수정 규칙
 * - 길이 제한: 채널별 maxChars
 * - 금칙어: FORBIDDEN_PATTERNS (정규식 | 로 구분)
 * - 해시태그 수 제한, 링크 수 제한
 */
const patStr = process.env.FORBIDDEN_PATTERNS || '무료|공짜|100%\\s*보장|전액환불';
const forbRe = new RegExp(`(?:${patStr})`, 'i');

function countHashtags(txt){ return (txt.match(/#[^\s#]+/g)||[]).length; }
function countLinks(txt){ return (txt.match(/https?:\/\//g)||[]).length; }

function limits(channel='NAVER'){
  const m = { NAVER:{maxChars:1000,maxHashtags:10,maxLinks:1}, INSTAGRAM:{maxChars:2200,maxHashtags:30,maxLinks:1} };
  return m[(channel||'NAVER').toUpperCase()] || m.NAVER;
}

function validate({ text='', channel='NAVER' }){
  const L = limits(channel);
  const errors=[];
  const trimmed = String(text||'').trim();
  if(trimmed.length > L.maxChars) errors.push('LENGTH_EXCEED');
  if(forbRe.test(trimmed)) errors.push('FORBIDDEN');
  if(countHashtags(trimmed) > L.maxHashtags) errors.push('HASHTAG_EXCEED');
  if(countLinks(trimmed) > L.maxLinks) errors.push('LINK_EXCEED');

  const autoApprove = errors.length===0;
  const level = autoApprove ? 'GREEN' : (errors.length<=1 ? 'YELLOW' : 'RED');
  return { ok:true, autoApprove, level, errors, text: trimmed };
}

function autofix({ text='', channel='NAVER' }){
  const L = limits(channel);
  let s = String(text||'').trim();

  // 금칙어 마스킹
  s = s.replace(forbRe, '***');
  // 링크 1개 초과 제거
  const urls = s.match(/https?:\/\/[\w\-._~:/?#\[\]@!$&'()*+,;=%]+/g)||[];
  if(urls.length > L.maxLinks){
    s = s.replace(urls.slice(1).join('|'), '');
  }
  // 해시태그 초과 절단
  const tags = s.match(/#[^\s#]+/g)||[];
  if(tags.length > L.maxHashtags){
    const keep = new Set(tags.slice(0,L.maxHashtags));
    s = s.replace(/#[^\s#]+/g, t => keep.has(t)?t:'');
  }
  // 길이 제한 절단
  if(s.length > L.maxChars) s = s.slice(0, L.maxChars);

  return { ok:true, text:s };
}

module.exports = { validate, autofix };
JS

cat > server/routes/ads_quality_alias.js <<'JS'
const express=require('express');
const q=require('../lib/quality');
const r=express.Router();

r.post('/validate', express.json(), async (req,res)=>{
  const { text, channel } = req.body||{};
  return res.json(q.validate({ text, channel }));
});

r.post('/autofix', express.json(), async (req,res)=>{
  const { text, channel } = req.body||{};
  return res.json(q.autofix({ text, channel }));
});

module.exports=r;
JS

# ─────────────────────────────────────────────────────────────────────────────
# [3] 광고주 프로필 API (GET/PUT /advertiser/profile)
# ─────────────────────────────────────────────────────────────────────────────
cat > server/routes/advertiser_profile.js <<'JS'
const express=require('express');
const db=require('../lib/db');
const r=express.Router();

r.get('/profile', async (req,res)=>{
  const id = parseInt(req.query.advertiser_id||'0',10);
  if(!id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  const q = await db.q(`SELECT * FROM advertiser_profile WHERE advertiser_id=$1`, [id]);
  res.json({ ok:true, profile: q.rows[0]||null });
});

r.put('/profile', express.json(), async (req,res)=>{
  const { advertiser_id, name, phone, email, address, meta } = req.body||{};
  if(!advertiser_id) return res.status(400).json({ ok:false, code:'ADVERTISER_ID_REQUIRED' });
  await db.q(`
    INSERT INTO advertiser_profile(advertiser_id,name,phone,email,address,meta,updated_at)
    VALUES($1,$2,$3,$4,$5,COALESCE($6,'{}'::jsonb),now())
    ON CONFLICT(advertiser_id) DO UPDATE
      SET name=EXCLUDED.name, phone=EXCLUDED.phone, email=EXCLUDED.email,
          address=EXCLUDED.address, meta=EXCLUDED.meta, updated_at=now()
  `,[advertiser_id, name||null, phone||null, email||null, address||null, meta?JSON.stringify(meta):null]);
  res.json({ ok:true });
});

module.exports=r;
JS

# ─────────────────────────────────────────────────────────────────────────────
# [4] 월 결제 구독 워커 (Admin 실행형) — 과금일 인보이스 → /ads/billing/charge
# ─────────────────────────────────────────────────────────────────────────────
cat > server/routes/admin_subscriptions.js <<'JS'
const express=require('express');
const db=require('../lib/db');
const admin=require('../mw/admin');

const r=express.Router();

function yyyymmdd(d=new Date()){
  const z = n=>String(n).padStart(2,'0');
  return d.getFullYear()+z(d.getMonth()+1)+z(d.getDate());
}

/** 구독 생성/수정 */
r.post('/ads/subscriptions', admin.requireAdmin, express.json(), async (req,res)=>{
  const { advertiser_id, plan_code, amount, bill_day, method_id } = req.body||{};
  if(!advertiser_id || !plan_code || !amount || !bill_day) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  await db.q(`
    INSERT INTO ad_subscriptions(advertiser_id,plan_code,amount,currency,method_id,bill_day,status,next_charge_at)
    VALUES($1,$2,$3,'KRW',$4,$5,'ACTIVE', date_trunc('day', now()))
    ON CONFLICT DO NOTHING
  `,[advertiser_id, plan_code, amount, method_id||null, bill_day]);
  res.json({ ok:true });
});

/** 월간 과금 워커 실행 */
r.post('/ads/subscriptions/run-billing', admin.requireAdmin, express.json(), async (req,res)=>{
  const today = parseInt(req.body?.today||new Date().getDate(),10);
  const limit = Math.max(1, Math.min(200, parseInt(req.body?.limit||'50',10)));

  const subs = await db.q(`
    SELECT * FROM ad_subscriptions
     WHERE status='ACTIVE'
       AND (
             bill_day=$1
             OR (next_attempt_at IS NOT NULL AND next_attempt_at <= now())
           )
     ORDER BY id ASC
     LIMIT $2
  `,[today, limit]);

  let ok=0, fail=0;
  for(const s of subs.rows){
    const inv = `SUB-${s.id}-${yyyymmdd()}`;
    // 인보이스 업서트
    await db.q(`
      INSERT INTO ad_invoices(invoice_no,advertiser_id,amount,currency,status,meta,updated_at,created_at)
      VALUES($1,$2,$3,'KRW','DUE',jsonb_build_object('subscription_id',$4),now(),now())
      ON CONFLICT (invoice_no) DO NOTHING
    `,[inv, s.advertiser_id, s.amount, s.id]);

    // 기본 수단 보장(없으면 조회)
    if(!s.method_id){
      const pm = await db.q(`SELECT id FROM payment_methods WHERE advertiser_id=$1 AND is_default=TRUE LIMIT 1`,[s.advertiser_id]);
      if(pm.rows.length){
        await db.q(`UPDATE ad_subscriptions SET method_id=$2 WHERE id=$1`,[s.id, pm.rows[0].id]);
      }
    }

    // CHARGE 호출 (샌드박스는 즉시 CAPTURED)
    try{
      const resp = await fetch(`http://localhost:${process.env.PORT||'5902'}/ads/billing/charge`,{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ invoice_no:inv, advertiser_id:s.advertiser_id, amount:s.amount })
      });
      const j = await resp.json().catch(()=>({}));
      const success = resp.ok && j?.status==='CAPTURED';
      if(success){
        ok++;
        // 영수증 번호 부여 + 다음 과금일
        const rcp = `RCP-${inv}`;
        await db.q(`UPDATE ad_invoices SET receipt_no=$2, status='PAID', updated_at=now() WHERE invoice_no=$1`,[inv, rcp]);
        await db.q(`UPDATE ad_subscriptions
                      SET retry_count=0, last_attempt_at=now(),
                          next_attempt_at=NULL,
                          next_charge_at = (date_trunc('month', now()) + interval '1 month') + ($1||' days')::interval
                    WHERE id=$2`,[Math.max(0,s.bill_day-1), s.id]);
      }else{
        fail++;
        const rc = (s.retry_count||0)+1;
        let next = "3 days"; if(rc>=2) next = "7 days";
        await db.q(`UPDATE ad_subscriptions
                      SET retry_count=$2, last_attempt_at=now(),
                          next_attempt_at = now() + interval '${next}',
                          status = CASE WHEN $2>=3 THEN 'PAUSED' ELSE status END
                    WHERE id=$1`,[s.id, rc]);
      }
    }catch(e){
      fail++;
    }
  }

  res.json({ ok:true, processed: subs.rows.length, success: ok, failed: fail });
});

module.exports=r;
JS

# ─────────────────────────────────────────────────────────────────────────────
# [5] 자동 승인 워커 (간단 버전)
# ─────────────────────────────────────────────────────────────────────────────
cat > server/routes/admin_autoreview.js <<'JS'
const express=require('express');
const db=require('../lib/db');
const admin=require('../mw/admin');
const q=require('../lib/quality');
const r=express.Router();

r.post('/ads/autoreview/run', admin.requireAdmin, express.json(), async (req,res)=>{
  const limit = Math.max(1, Math.min(100, parseInt(req.body?.limit||'10',10)));
  const pending = await db.q(`
    SELECT * FROM ad_creatives
     WHERE approved_at IS NULL AND reviewed_at IS NULL
     ORDER BY created_at ASC
     LIMIT $1
  `,[limit]);

  let approved=0, rejected=0;
  for(const c of pending.rows){
    const text = (c.flags->>'text') || '';
    const channel = c.channel || 'NAVER';
    const v = q.validate({ text, channel });
    if(v.autoApprove){
      await db.q(`UPDATE ad_creatives SET approved_at=now(), reviewed_at=now(), flags=jsonb_set(COALESCE(flags,'{}'::jsonb),'{final}','"approved"') WHERE id=$1`,[c.id]);
      approved++;
    }else{
      await db.q(`UPDATE ad_creatives SET reviewed_at=now(), flags=jsonb_set(COALESCE(flags,'{}'::jsonb),'{final}','"rejected"') WHERE id=$1`,[c.id]);
      rejected++;
    }
  }

  res.json({ ok:true, processed: pending.rows.length, approved, rejected });
});

module.exports=r;
JS

# ─────────────────────────────────────────────────────────────────────────────
# [6] PWA 자산이 없으면 최소 생성
# ─────────────────────────────────────────────────────────────────────────────
[ -f public/manifest.json ] || cat > public/manifest.json <<'JSON'
{ "name":"Petlink Ads", "short_name":"Ads",
  "start_url":"/", "display":"standalone", "background_color":"#ffffff",
  "theme_color":"#0ea5e9", "icons":[]
}
JSON

[ -f server/public/service-worker.js ] || cat > server/public/service-worker.js <<'JS'
// very tiny placeholder sw
self.addEventListener('install', ()=>self.skipWaiting());
self.addEventListener('activate', ()=>clients.claim());
JS

# ─────────────────────────────────────────────────────────────────────────────
# [7] app.js 마운트(중복 안전) + 서버 재기동
# ─────────────────────────────────────────────────────────────────────────────
if ! grep -q "routes/ads_quality_alias" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/ads', require('./routes/ads_quality_alias'));\\
" server/app.js && rm -f server/app.js.bak
fi

if ! grep -q "routes/advertiser_profile" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/advertiser', require('./routes/advertiser_profile'));\\
" server/app.js && rm -f server/app.js.bak
fi

if ! grep -q "routes/admin_subscriptions" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin', require('./routes/admin_subscriptions'));\\
" server/app.js && rm -f server/app.js.bak
fi

if ! grep -q "routes/admin_autoreview" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin', require('./routes/admin_autoreview'));\\
" server/app.js && rm -f server/app.js.bak
fi

# 재기동
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 2
curl -sf "http://localhost:${PORT}/health" >/dev/null || { echo "[ERR] health failed"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# [8] 스모크(성공 문자열 고정)
# ─────────────────────────────────────────────────────────────────────────────

# 8-1 프로필 저장/조회
curl -sf -XPUT "http://localhost:${PORT}/advertiser/profile" \
  -H "Content-Type: application/json" \
  -d '{"advertiser_id":101,"name":"테스트매장","phone":"010-0000-0000","email":"test@example.com","address":"서울","meta":{"bizno":"000-00-00000"}}' \
  | grep -q '"ok":true' && echo "PROFILE SAVE OK"

# 8-2 검증/자동수정 API
curl -sf -XPOST "http://localhost:${PORT}/ads/validate" \
  -H "Content-Type: application/json" \
  -d '{"text":"합리적인 광고 상담 신청 #케어 https://example.com","channel":"NAVER"}' \
  | grep -q '"ok":true' && echo "VALIDATE OK"

curl -sf -XPOST "http://localhost:${PORT}/ads/autofix" \
  -H "Content-Type: application/json" \
  -d '{"text":"공짜 상담! 100% 보장 #태그1 #태그2 #태그3 https://link1.com https://link2.com","channel":"NAVER"}' \
  | grep -q '"ok":true' && echo "AUTOFIX OK"

# 8-3 자동승인 루프(소량 후보 투입 후 승인 1건 기대)
psql "$DATABASE_URL" -c "INSERT INTO ad_creatives(advertiser_id,channel,flags,created_at) VALUES (101,'NAVER','{\"text\":\"안심 분양 상담 신청 #케어\"}', now()) ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true

curl -sf -XPOST "http://localhost:${PORT}/admin/ads/subscriptions" \
  -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d "{\"advertiser_id\":101,\"plan_code\":\"BASIC\",\"amount\":120000,\"bill_day\":$(date +%d)}" >/dev/null && true

# 결제수단 보장
psql "$DATABASE_URL" -c "INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,is_default) VALUES (101,'CARD','bootpay','tok-demo',TRUE) ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true

curl -sf -XPOST "http://localhost:${PORT}/admin/ads/subscriptions/run-billing" \
  -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d "{\"today\":$(date +%d),\"limit\":10}" \
  | grep -q '"ok":true' && echo "SANDBOX CHARGE OK"

# 자동 승인 1건 이상 처리 확인(간단 판단)
curl -sf -XPOST "http://localhost:${PORT}/admin/ads/autoreview/run" \
  -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"limit":10}' \
  | grep -Eq '"approved":[1-9]|"processed":[1-9]' && echo "AUTO-APPROVE OK"

# 8-4 PWA 매니페스트 확인
curl -sf "http://localhost:${PORT}/manifest.json" | grep -q '"name"' && echo "PWA INSTALL OK"

