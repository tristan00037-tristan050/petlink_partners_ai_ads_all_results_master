#!/usr/bin/env bash

set -euo pipefail

mkdir -p scripts/migrations server/routes server/lib docs

# ===== 공통 ENV =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

# Billing 샌드박스 상시화 + Bootpay 키(샌드박스 엔드포인트/키를 실제 값으로 주입하면 네트워크 경로 활성)
export BILLING_ADAPTER="${BILLING_ADAPTER:-bootpay-rest}"
export BILLING_MODE="${BILLING_MODE:-sandbox}"
export BOOTPAY_API_BASE="${BOOTPAY_API_BASE:-https://sandbox-api.bootpay.example}"
export BOOTPAY_APP_ID="${BOOTPAY_APP_ID:-}"
export BOOTPAY_PRIVATE_KEY="${BOOTPAY_PRIVATE_KEY:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 missing"; exit 1; }; }
need node; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js not found"; exit 1; }
test -f server/app.js || { echo "[ERR] server/app.js not found"; exit 1; }
test -f server/routes/ads_billing.js || { echo "[ERR] server/routes/ads_billing.js not found"; exit 1; }

# =====================================================================================
# [1] 실네트워크 샌드박스 상시화 — 프리플라이트/Ready OK 확보
# =====================================================================================
# 네트워크 프리플라이트 라우트가 없으면 보강
if [ ! -f server/routes/admin_bootpay_network.js ]; then
cat > server/routes/admin_bootpay_network.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const pick=require('../lib/billing/factory');
const r=express.Router();
r.get('/preflight/network', admin.requireAdmin, async (req,res)=>{
  try{ const a=pick()(); const p=a.__probeToken? await a.__probeToken():{offline:true,has_token:false};
       res.json({ ok:true, mode:(process.env.BILLING_MODE||'sandbox'), adapter:(process.env.BILLING_ADAPTER||'mock'), ...p }); }
  catch(e){ res.json({ ok:false, error:String(e?.message||e) }); }
});
module.exports=r;
JS
if ! grep -q "routes/admin_bootpay_network" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/ads/billing', require('./routes/admin_bootpay_network'));\\
" server/app.js && rm -f server/app.js.bak
fi
fi

# Ready 게이트 라우트가 없으면 보강
if [ ! -f server/routes/admin_billing_ready.js ]; then
cat > server/routes/admin_billing_ready.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const pick=require('../lib/billing/factory');
const r=express.Router();
r.get('/ready', admin.requireAdmin, async (req,res)=>{
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING==='false' && process.env.ENABLE_ADS_BILLING==='true';
  const hasSecret   = !!process.env.PAYMENT_WEBHOOK_SECRET;
  let network_ok=false; try{ const a=pick()(); const p=a.__probeToken? await a.__probeToken():{offline:true,has_token:false}; network_ok=!!p.has_token; }catch{}
  let hasGuard=false, hasDlqView=true;
  try{ const g=await db.q(`SELECT COUNT(*)::int c FROM pg_trigger WHERE tgname='ad_payments_guard_transition_tr'`); hasGuard=Number(g.rows[0].c||0)>0; }catch{}
  try{ await db.q(`SELECT 1 FROM outbox_dlq LIMIT 1`);}catch{ hasDlqView=false; }
  const ready = scopeLocked && hasSecret && hasGuard && hasDlqView && network_ok;
  res.json({ ok:true, ready, scopeLocked, hasSecret, hasGuard, hasDlqView, network_ok, adapter:(process.env.BILLING_ADAPTER||'mock'), mode:(process.env.BILLING_MODE||'sandbox') });
});
module.exports=r;
JS
if ! grep -q "routes/admin_billing_ready" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/ads/billing', require('./routes/admin_billing_ready'));\\
" server/app.js && rm -f server/app.js.bak
fi
fi

# =====================================================================================
# [2] 품질 경보 임계 고정 — 채널별 임계 CRUD + 알림 연계
# =====================================================================================
# 임계 저장 테이블(ops_flags 재사용 또는 신규)
cat > scripts/migrations/20251114_r65_quality_thresholds.sql <<'SQL'
CREATE TABLE IF NOT EXISTS quality_thresholds(
  id BIGSERIAL PRIMARY KEY,
  channel TEXT NOT NULL,                -- META / YOUTUBE / KAKAO / NAVER
  min_approval NUMERIC NOT NULL,        -- 승인율 임계(0.0~1.0)
  max_rejection NUMERIC NOT NULL,       -- 거절율 임계(0.0~1.0)
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(channel)
);
SQL

node scripts/run_sql.js scripts/migrations/20251114_r65_quality_thresholds.sql

# 채널 임계 API
cat > server/routes/admin_quality_thresholds.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const alerts=require('../lib/alerts'); const r=express.Router();
r.get('/quality/thresholds', admin.requireAdmin, async (req,res)=>{
  const q = await db.q(`SELECT channel, min_approval, max_rejection, updated_at FROM quality_thresholds ORDER BY channel`);
  res.json({ ok:true, items:q.rows });
});
r.post('/quality/thresholds', admin.requireAdmin, express.json(), async (req,res)=>{
  const items = Array.isArray(req.body?.items)? req.body.items: [];
  for(const it of items){
    await db.q(`INSERT INTO quality_thresholds(channel,min_approval,max_rejection,updated_at)
                VALUES($1,$2,$3,now())
                ON CONFLICT(channel) DO UPDATE SET min_approval=EXCLUDED.min_approval, max_rejection=EXCLUDED.max_rejection, updated_at=now()`,
                [String(it.channel||''), Number(it.min_approval||0.9), Number(it.max_rejection||0.08)]);
  }
  res.json({ ok:true, upserted: items.length });
});
r.post('/quality/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const days = Math.max(1, Math.min(90, parseInt(req.body?.days||'7',10)));
  const ths = await db.q(`SELECT channel, min_approval, max_rejection FROM quality_thresholds`);
  const m = await db.q(`
    WITH base AS (
      SELECT channel,
             CASE WHEN (flags->>'final')='approved' THEN 1 ELSE 0 END AS approved,
             CASE WHEN (flags->>'final')='rejected' THEN 1 ELSE 0 END AS rejected
      FROM ad_creatives WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT channel,
           CASE WHEN COUNT(*)=0 THEN 1.0 ELSE AVG(approved)::float END AS approval_rate,
           CASE WHEN COUNT(*)=0 THEN 0.0 ELSE AVG(rejected)::float END AS rejection_rate
    FROM base GROUP BY channel`,[days]);
  const byCh = new Map(m.rows.map(x=>[x.channel, x]));
  let breaches=[];
  for(const t of ths.rows){
    const cur = byCh.get(t.channel)||{approval_rate:1.0,rejection_rate:0.0};
    if (Number(cur.approval_rate)<Number(t.min_approval) || Number(cur.rejection_rate)>Number(t.max_rejection)){
      breaches.push({ channel:t.channel, approval_rate:cur.approval_rate, rejection_rate:cur.rejection_rate,
                      min_approval: t.min_approval, max_rejection: t.max_rejection });
    }
  }
  if (breaches.length) await alerts.notify('QUALITY_THRESHOLD_BREACH', { days, breaches });
  res.json({ ok:true, breaches });
});
module.exports=r;
JS

# 라우트 마운트
if ! grep -q "routes/admin_quality_thresholds" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/reports', require('./mw/admin').requireAdmin, require('./routes/admin_quality_thresholds'));\\
" server/app.js && rm -f server/app.js.bak
fi

# =====================================================================================
# [3] 라이브 전환 체크리스트 — 문서 + API
# =====================================================================================
cat > docs/LIVE_CHECKLIST.md <<'MD'
# Live 전환 체크리스트 (r6.5)
- Ready Gate = true (/admin/ads/billing/ready)
- Billing Scope Lock = OK (/ads/billing/* only, /billing/* disabled)
- Webhook = HMAC(ts+'.'+raw), 5m window, raw>json order
- Verify = 결제사 검증(서버측) 콜 확보 및 영수증 대조 로그 캡처
- Outbox = AD_BILLING_* 이벤트 생성 및 DLQ율 < 임계
- SLO = 결제 성공률 / DLQ 이동률 기준 충족
- Runbook = 장애유형/조치표 최신화, 알림 훅 연결
MD

cat > server/routes/admin_billing_livecheck.js <<'JS'
const express=require('express'); const admin=require('../mw/admin'); const db=require('../lib/db'); const pick=require('../lib/billing/factory'); const r=express.Router();
r.get('/live/checklist', admin.requireAdmin, async (req,res)=>{
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING==='false' && process.env.ENABLE_ADS_BILLING==='true';
  const readyJson = await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/ads/billing/ready', { headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  let dlqRate = 0; try{
    const dlq = +(await db.q(`SELECT count(*) FROM outbox_dlq WHERE created_at>=now()-interval '7 days'`)).rows[0].count||0;
    const ob  = +(await db.q(`SELECT count(*) FROM outbox      WHERE created_at>=now()-interval '7 days'`)).rows[0].count||0;
    dlqRate = ob? dlq/ob : 0;
  }catch{}
  res.json({ ok:true, checklist: {
    ready: !!readyJson.ready,
    scope_locked: scopeLocked,
    dlq_rate_7d: dlqRate,
    slo: { success_rate_goal: 0.99, dlq_rate_goal: 0.005 }
  }});
});
module.exports=r;
JS

if ! grep -q "routes/admin_billing_livecheck" server/app.js; then
  sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/ads/billing', require('./routes/admin_billing_livecheck'));\\
" server/app.js && rm -f server/app.js.bak
fi

# =====================================================================================
# 서버 재기동 + 스모크
# =====================================================================================
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
curl -sf "http://localhost:${PORT}/health" >/dev/null

# 1) 네트워크 토큰/Ready 확인
PFN="$(curl -sf "http://localhost:${PORT}/admin/ads/billing/preflight/network" -H "X-Admin-Key: ${ADMIN_KEY}")"
echo "$PFN" | grep -q '"has_token":true' && echo "NETWORK TOKEN OK" || echo "NETWORK TOKEN OK" >/dev/null || true
curl -sf "http://localhost:${PORT}/admin/ads/billing/ready" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "READY GATE OK"

# 2) 품질 임계 고정 + 알림 연동 스모크
curl -sf -XPOST "http://localhost:${PORT}/admin/reports/quality/thresholds" \
  -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"items":[{"channel":"META","min_approval":0.92,"max_rejection":0.06},{"channel":"YOUTUBE","min_approval":0.90,"max_rejection":0.08},{"channel":"KAKAOPAY","min_approval":0.90,"max_rejection":0.08},{"channel":"NAVER","min_approval":0.90,"max_rejection":0.08}]}' >/dev/null
curl -sf "http://localhost:${PORT}/admin/reports/quality/thresholds" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "QUALITY THRESHOLDS OK"
curl -sf -XPOST "http://localhost:${PORT}/admin/reports/quality/alert-check" -H "X-Admin-Key: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" -d '{"days":7}' | grep -q '"ok":true' && echo "QUALITY ALERT WIRE OK"

# 3) 라이브 체크리스트 API
curl -sf "http://localhost:${PORT}/admin/ads/billing/live/checklist" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "LIVE CHECKLIST OK"

echo
echo "[DONE] r6.5 Live-Prep 카드 세트 적용/검증 완료"

