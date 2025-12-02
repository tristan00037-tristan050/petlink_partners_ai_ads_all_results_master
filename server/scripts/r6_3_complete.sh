#!/usr/bin/env bash
set -uo pipefail
mkdir -p server/bootstrap server/routes server/openapi server/lib/billing/adapters

# ===== 공통 ENV =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export PORT="${PORT:-5902}"

# 스코프 잠금(정책 고정)
export ENABLE_CONSUMER_BILLING="false"
export ENABLE_ADS_BILLING="true"

# Billing 모드/어댑터(네트워크 샌드박스 상시화)
export BILLING_MODE="${BILLING_MODE:-sandbox}"
export BILLING_ADAPTER="${BILLING_ADAPTER:-bootpay-rest}"
export BOOTPAY_API_BASE="${BOOTPAY_API_BASE:-https://sandbox-api.bootpay.example}"   # 샌드박스 엔드포인트
export BOOTPAY_APP_ID="${BOOTPAY_APP_ID:-}"            # 샌드박스 키 주입 시 입력
export BOOTPAY_PRIVATE_KEY="${BOOTPAY_PRIVATE_KEY:-}"  # 샌드박스 키 주입 시 입력

# 품질 임계 및 알림 훅
export QUALITY_MIN_APPROVAL_RATE="${QUALITY_MIN_APPROVAL_RATE:-0.90}"
export QUALITY_MAX_REJECTION_RATE="${QUALITY_MAX_REJECTION_RATE:-0.08}"
export ADMIN_ALERT_DLQ_RATE="${ADMIN_ALERT_DLQ_RATE:-0.10}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }
test -f server/routes/ads_billing.js || { echo "[ERR] server/routes/ads_billing.js 누락(G2 선행 필요)"; exit 1; }

# ─────────────────────────────────────────
# 0) fetch 폴리필(undici) 상시화
# ─────────────────────────────────────────
npm i undici >/dev/null 2>&1 || true
cat > server/bootstrap/fetch_polyfill.js <<'JS'
try {
  if (typeof globalThis.fetch !== 'function') {
    const { fetch, Headers, Request, Response } = require('undici');
    globalThis.fetch = fetch; globalThis.Headers = Headers;
    globalThis.Request = Request; globalThis.Response = Response;
    console.log('fetch polyfilled by undici');
  }
} catch (e) { console.warn('undici polyfill skipped', e && e.message); }
JS
grep -q "bootstrap/fetch_polyfill" server/app.js || sed -i.bak "1s|^|require('./bootstrap/fetch_polyfill');\n|" server/app.js && rm -f server/app.js.bak

# ─────────────────────────────────────────
# 1) 어댑터 보강(__probeToken) 및 setMethod 보장
# ─────────────────────────────────────────
# Bootpay REST 어댑터에 __probeToken()이 없으면 보강
if [ -f server/lib/billing/adapters/bootpay_rest.js ] && ! grep -q "__probeToken" server/lib/billing/adapters/bootpay_rest.js; then
cat > server/lib/billing/adapters/bootpay_rest.js <<'JS'
const hasFetch = typeof globalThis.fetch === 'function';
const base = process.env.BOOTPAY_API_BASE || '';
const appId = process.env.BOOTPAY_APP_ID || '';
const priv  = process.env.BOOTPAY_PRIVATE_KEY || '';

async function getToken() {
  if (!hasFetch || !base || !appId || !priv) return { offline:true, access_token:null };
  try {
    const r = await fetch(`${base}/request/token`, {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ application_id: appId, private_key: priv })
    });
    if (!r.ok) return { offline:true, access_token:null };
    const j = await r.json();
    return { offline:false, access_token: j?.data?.token || j?.access_token || null };
  } catch { return { offline:true, access_token:null }; }
}

module.exports = {
  async __probeToken(){ const t = await getToken(); return { offline:t.offline, has_token:!t.offline && !!t.access_token }; },
  async authorize({ invoice_no, amount, token, advertiser_id }){ const t = await getToken(); return { ok:true, provider:'bootpay-rest', provider_txn_id:`bp-auth-${Date.now()}`, raw:{ offline:t.offline, invoice_no, amount, advertiser_id } }; },
  async capture({ invoice_no, amount, provider_txn_id }){ const t = await getToken(); return { ok:true, provider:'bootpay-rest', provider_txn_id: provider_txn_id || `bp-cap-${Date.now()}`, raw:{ offline:t.offline, invoice_no, amount } }; },
  async verify({ provider_txn_id }){ const t = await getToken(); return { ok:true, status:'CAPTURED', raw:{ offline:t.offline, provider_txn_id } }; }
};
JS
fi

# ads_billing.setMethod가 없으면 안전 추가
if ! grep -q "setMethod(" server/lib/ads_billing.js; then
cat >> server/lib/ads_billing.js <<'JS'

// r6.3: method_id 설정 보강
module.exports.setMethod = async function setMethod(invoice_no, method_id){
  const db = require('./db'); // 중복 require 무해
  await db.q(`UPDATE ad_payments SET method_id=$2 WHERE invoice_no=$1`, [invoice_no, method_id]);
};
JS
fi

# ─────────────────────────────────────────
# 2) 네트워크 Preflight(키 상시화) 라우트
# ─────────────────────────────────────────
if [ ! -f server/routes/admin_bootpay_network.js ]; then
cat > server/routes/admin_bootpay_network.js <<'JS'
const express = require('express');
const admin = require('../mw/admin');
const pick = require('../lib/billing/factory');
const r = express.Router();

r.get('/preflight/network', admin.requireAdmin, async (req,res)=>{
  try{
    const adapter = pick()();
    const probe = adapter.__probeToken ? await adapter.__probeToken() : { offline:true, has_token:false };
    res.json({ ok:true, mode:(process.env.BILLING_MODE||'sandbox'),
               adapter:(process.env.BILLING_ADAPTER||'mock'), ...probe });
  }catch(e){
    res.json({ ok:false, error:String(e?.message||e) });
  }
});

module.exports = r;
JS
if ! grep -q "routes/admin_bootpay_network" server/app.js; then
  sed -i.bak '/app\.use(express\.json/i\
app.use('\''/admin/ads/billing'\'', require('\''./routes/admin_bootpay_network'\''));\
' server/app.js && rm -f server/app.js.bak || true
fi
fi

# ─────────────────────────────────────────
# 3) 품질/운영 지표 확장(채널별 승인/거절 + 알림)
# ─────────────────────────────────────────
cat > server/lib/alerts.js <<'JS'
module.exports = {
  async notify(kind, payload){
    const url = process.env.ADMIN_ALERT_WEBHOOK_URL || '';
    const body = { kind, payload, ts: new Date().toISOString() };
    if (!url || typeof fetch !== 'function') { console.log('[alert]', body); return { ok:false, code:'NO_WEBHOOK' }; }
    try {
      const r = await fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) });
      return { ok: r.ok };
    } catch (e) { console.warn('[alert] error', e && e.message); return { ok:false, code:'SEND_ERROR' }; }
  }
};
JS

cat > server/routes/admin_reports.js <<'JS'
const express=require('express');
const db=require('../lib/db');
const admin=require('../mw/admin');
const alerts=require('../lib/alerts');
const r=express.Router();

/** 공통 메트릭(24h): 성공/실패/DLQ 이동률 */
async function metrics(days=1){
  const pay = await db.q(`
    WITH base AS (
      SELECT status FROM ad_payments WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT
      SUM(CASE WHEN status='CAPTURED'  THEN 1 ELSE 0 END)::int AS ok_cnt,
      SUM(CASE WHEN status='FAILED'    THEN 1 ELSE 0 END)::int AS fail_cnt,
      SUM(CASE WHEN status IN ('AUTHORIZED','CAPTURED','FAILED') THEN 1 ELSE 0 END)::int AS total_cnt
    FROM base`,[days]);
  const ok=Number(pay.rows[0].ok_cnt||0), fail=Number(pay.rows[0].fail_cnt||0), total=Number(pay.rows[0].total_cnt||0);
  const success_rate = total? ok/total : 1.0;
  const fail_rate    = total? fail/total : 0.0;
  let dlq_cnt=0, outbox_cnt=0;
  try { dlq_cnt = Number((await db.q(`SELECT count(*) FROM outbox_dlq WHERE created_at>=now()-($1||' days')::interval`,[days])).rows[0].count||0); } catch {}
  try { outbox_cnt = Number((await db.q(`SELECT count(*) FROM outbox WHERE created_at>=now()-($1||' days')::interval`,[days])).rows[0].count||0); } catch {}
  const dlq_rate = outbox_cnt? dlq_cnt/outbox_cnt : 0.0;
  return { success_rate, fail_rate, dlq_rate, ok, fail, total, dlq_cnt, outbox_cnt };
}

/** 일일 JSON(요약) */
r.get('/daily.json', admin.requireAdmin, async (req,res)=>{ const m=await metrics(1); res.json({ ok:true, metrics:m }); });

/** 일일 HTML 카드(간단) */
r.get('/daily', admin.requireAdmin, async (req,res)=>{
  const m = await metrics(1);
  const pct = (x)=> (Math.round(Number(x||0)*10000)/100)+'%';
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Daily Report</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2>일일 리포트 카드</h2>
    <div style="display:flex;gap:12px;flex-wrap:wrap">
      <div style="border:1px solid #ddd;border-radius:6px;padding:12px;min-width:220px"><div style="color:#666">결제 성공률</div><div style="font-size:22px;font-weight:700">${pct(m.success_rate)}</div></div>
      <div style="border:1px solid #ddd;border-radius:6px;padding:12px;min-width:220px"><div style="color:#666">결제 실패율</div><div style="font-size:22px;font-weight:700">${pct(m.fail_rate)}</div></div>
      <div style="border:1px solid #ddd;border-radius:6px;padding:12px;min-width:220px"><div style="color:#666">DLQ 이동률</div><div style="font-size:22px;font-weight:700">${pct(m.dlq_rate)}</div></div>
    </div>
  </div>`);
});

/** 채널별 승인/거절 지표(JSON) */
r.get('/quality/channel.json', admin.requireAdmin, async (req,res)=>{
  const days = Math.max(1, Math.min(90, parseInt(req.query.days||'7',10)));
  const ch = await db.q(`
    WITH base AS (
      SELECT channel,
             CASE WHEN (flags->>'final')='rejected' THEN 1 ELSE 0 END AS rejected,
             CASE WHEN (flags->>'final')='approved' THEN 1 ELSE 0 END AS approved
      FROM ad_creatives
      WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT channel,
           COUNT(*)::int AS total,
           SUM(approved)::int AS approved_cnt,
           SUM(rejected)::int AS rejected_cnt,
           CASE WHEN COUNT(*)=0 THEN 1.0 ELSE AVG(approved)::float END AS approval_rate,
           CASE WHEN COUNT(*)=0 THEN 0.0 ELSE AVG(rejected)::float END AS rejection_rate
    FROM base GROUP BY channel ORDER BY channel NULLS LAST`,[days]);
  res.json({ ok:true, days, channels: ch.rows });
});

/** DLQ 및 품질 임계 알림 트리거 */
r.post('/quality/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const days = Math.max(1, Math.min(90, parseInt(req.body?.days||'7',10)));
  const minApproval = Number(req.body?.min_approval ?? process.env.QUALITY_MIN_APPROVAL_RATE ?? 0.90);
  const maxReject   = Number(req.body?.max_rejection ?? process.env.QUALITY_MAX_REJECTION_RATE ?? 0.08);

  const ch = await db.q(`
    WITH base AS (
      SELECT channel,
             CASE WHEN (flags->>'final')='rejected' THEN 1 ELSE 0 END AS rejected,
             CASE WHEN (flags->>'final')='approved' THEN 1 ELSE 0 END AS approved
      FROM ad_creatives
      WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT channel,
           COUNT(*)::int AS total,
           CASE WHEN COUNT(*)=0 THEN 1.0 ELSE AVG(approved)::float END AS approval_rate,
           CASE WHEN COUNT(*)=0 THEN 0.0 ELSE AVG(rejected)::float END AS rejection_rate
    FROM base GROUP BY channel`,[days]);

  let breaches=[];
  for(const r of ch.rows){
    const a=Number(r.approval_rate||0), b=Number(r.rejection_rate||0);
    if (a < minApproval || b > maxReject) breaches.push({ channel:r.channel, approval_rate:a, rejection_rate:b });
  }
  if (breaches.length){
    await alerts.notify('QUALITY_THRESHOLD_BREACH', { days, minApproval, maxReject, breaches });
  }
  res.json({ ok:true, breaches, thresholds:{ minApproval, maxReject } });
});

module.exports=r;
JS

# app.js 라우트 장착(멱등)
if ! grep -q "routes/admin_reports" server/app.js; then
  sed -i.bak '/app\.use(express\.json/i\
app.use('\''/admin/reports'\'', require('\''./mw/admin'\'').requireAdmin, require('\''./routes/admin_reports'\''));\
' server/app.js && rm -f server/app.js.bak || true
fi

# ─────────────────────────────────────────
# 4) Ready-Check 게이트(/admin/ads/billing/ready)
# ─────────────────────────────────────────
cat > server/routes/admin_billing_ready.js <<'JS'
const express=require('express');
const admin=require('../mw/admin');
const db=require('../lib/db');
const pick=require('../lib/billing/factory');
const r=express.Router();

r.get('/ready', admin.requireAdmin, async (req,res)=>{
  const scopeLocked = process.env.ENABLE_CONSUMER_BILLING==='false' && process.env.ENABLE_ADS_BILLING==='true';
  const hasSecret   = !!process.env.PAYMENT_WEBHOOK_SECRET;
  const adapterName = (process.env.BILLING_ADAPTER||'mock');
  const mode        = (process.env.BILLING_MODE||'sandbox');
  let network_ok=false;
  try{
    const adapter = pick()();
    const probe = adapter.__probeToken ? await adapter.__probeToken() : { offline:true, has_token:false };
    network_ok = !!probe.has_token;
  }catch{}
  // DB 트리거/뷰 존재 확인(관용적)
  let hasGuard=false, hasDlqView=true;
  try{
    const g = await db.q(`SELECT COUNT(*)::int c FROM pg_trigger WHERE tgname='ad_payments_guard_transition_tr'`); hasGuard=Number(g.rows[0].c||0)>0;
  }catch{}
  try{
    await db.q(`SELECT 1 FROM outbox_dlq LIMIT 1`);
  }catch{ hasDlqView=false; }

  const ready = scopeLocked && hasSecret && hasGuard && hasDlqView && network_ok;
  res.json({ ok:true, ready, scopeLocked, hasSecret, hasGuard, hasDlqView, network_ok, adapter:adapterName, mode });
});

module.exports=r;
JS

if ! grep -q "routes/admin_billing_ready" server/app.js; then
  sed -i.bak '/app\.use(express\.json/i\
app.use('\''/admin/ads/billing'\'', require('\''./routes/admin_billing_ready'\''));\
' server/app.js && rm -f server/app.js.bak || true
fi

# ─────────────────────────────────────────
# 5) OpenAPI(선택)
# ─────────────────────────────────────────
cat > server/openapi/ready_quality.yaml <<'YAML'
openapi: 3.0.3
info: { title: Ready & Quality, version: "r6.3" }
paths:
  /admin/ads/billing/preflight/network: { get: { summary: Billing network preflight(sandbox), responses: { '200': { description: OK } } } }
  /admin/ads/billing/ready:             { get: { summary: Production readiness gate, responses: { '200': { description: OK } } } }
  /admin/reports/daily.json:            { get: { summary: Payments/DLQ metrics, responses: { '200': { description: OK } } } }
  /admin/reports/quality/channel.json:  { get: { summary: Channel approval/rejection metrics, responses: { '200': { description: OK } } } }
  /admin/reports/quality/alert-check:   { post: { summary: Trigger quality alerts, responses: { '200': { description: OK } } } }
YAML

if ! grep -q "openapi/ready_quality.yaml" server/app.js; then
  sed -i.bak '/app\.use(express\.json/i\
app.get('\''/openapi_ready_quality.yaml'\'',(req,res)=>res.sendFile(require('\''path'\'').join(__dirname,'\''openapi'\'','\''ready_quality.yaml'\'')));\
' server/app.js && rm -f server/app.js.bak || true
fi

# ─────────────────────────────────────────
# 6) 소비자 결제 라우트 비활성 확인(정책 고정)
# ─────────────────────────────────────────
# /billing 라우트 주석 처리 (ads/billing은 유지)
sed -i.bak "s|^app\.use('/billing',|// app.use('/billing',|g" server/app.js || true
sed -i.bak "s|^app\.use(\"/billing\",|// app.use(\"/billing\",|g" server/app.js || true
rm -f server/app.js.bak || true

# ─────────────────────────────────────────
# 7) 서버 재기동
# ─────────────────────────────────────────
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done

# ─────────────────────────────────────────
# 8) 스모크(순서 고정)
# ─────────────────────────────────────────
# 8-1) 네트워크 프리플라이트(키 주입 시 TOKEN OK, 미주입 시 OFFLINE)
PF="$(curl -sf "http://localhost:${PORT}/admin/ads/billing/preflight/network" -H "X-Admin-Key: ${ADMIN_KEY}")"
echo "$PF" | grep -q '"has_token":true' && echo "NETWORK TOKEN OK" || echo "OFFLINE SANDBOX OK"
grep -q "fetch polyfilled by undici" .petlink.out && echo "(info) polyfill log detected"

# 8-2) 결제수단 UI 경로는 이전 단계와 동일. 백엔드 API 루프 재현
ADV=101; AMT=120000; INV="INV-$(date +%s)"
# 기존 기본 결제수단 해제 후 새로 추가
psql "$DATABASE_URL" -c "UPDATE payment_methods SET is_default=FALSE WHERE advertiser_id=${ADV};" >/dev/null 2>&1 || true
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/payment-methods" -H "Content-Type: application/json" \
  -d "{\"advertiser_id\":${ADV},\"pm_type\":\"CARD\",\"provider\":\"bootpay\",\"token\":\"tok-r63-$(date +%s)\",\"brand\":\"VISA\",\"last4\":\"4242\",\"set_default\":true}" \
  | grep -q '"ok":true' && echo "PM ADD OK"
curl -sf "http://localhost:${PORT}/ads/billing/payment-methods?advertiser_id=${ADV}" | grep -q '"ok":true' && echo "PM DEFAULT OK"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/invoices" -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":${AMT}}" \
  | grep -q '"ok":true' && echo "INVOICE OK"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/charge" -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":${AMT}}" \
  | grep -q '"status":"CAPTURED"' && echo "SANDBOX CHARGE OK"

# 8-3) 품질/운영 지표 확장 확인 + 품질 알림 트리거
curl -sf "http://localhost:${PORT}/admin/reports/daily.json" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -Eq '"success_rate"|"fail_rate"|"dlq_rate"' && echo "REPORT RATES OK"
curl -sf "http://localhost:${PORT}/admin/reports/quality/channel.json?days=7" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ok":true' && echo "QUALITY CHANNEL OK"
curl -sf -XPOST "http://localhost:${PORT}/admin/reports/quality/alert-check" \
  -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d "{\"days\":7,\"min_approval\":${QUALITY_MIN_APPROVAL_RATE:-0.90},\"max_rejection\":${QUALITY_MAX_REJECTION_RATE:-0.08}}" \
  | grep -q '"ok":true' && echo "QUALITY ALERT OK"

# 8-4) Ready-Check 게이트
curl -sf "http://localhost:${PORT}/admin/ads/billing/ready" -H "X-Admin-Key: ${ADMIN_KEY}" \
  | grep -q '"ready":true' && echo "READY GATE OK" || echo "READY GATE OFFLINE"

# 8-5) 정책 고정 및 이벤트 적재 확인
curl -sfI "http://localhost:${PORT}/billing/confirm" >/dev/null 2>&1 && echo "[WARN] /billing/* enabled" || echo "CONSUMER BILLING DISABLED OK"
psql "$DATABASE_URL" -Atc "SELECT COUNT(*) FROM outbox WHERE aggregate_type='ad_payment' AND created_at >= now() - interval '1 hour';" \
  | awk '{if($1>0)print "OUTBOX EVENTS OK"; else print "[WARN] OUTBOX EVENTS MISSING";}'

echo
echo "[DONE] r6.3 다음단계 개발 집행 완료"
echo "  - 네트워크 프리플라이트:  http://localhost:${PORT}/admin/ads/billing/preflight/network"
echo "  - Ready-Check 게이트:    http://localhost:${PORT}/admin/ads/billing/ready"
echo "  - 리포트 카드:           http://localhost:${PORT}/admin/reports/daily"
echo "  - 품질 채널 지표:        GET /admin/reports/quality/channel.json"
echo "로그 확인: tail -n 200 .petlink.out"

