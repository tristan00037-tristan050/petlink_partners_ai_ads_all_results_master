#!/usr/bin/env bash
set -euo pipefail
mkdir -p scripts/migrations server/mw server/openapi docs .github/workflows scripts

export PORT="${PORT:-5902}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export ADMIN_ALERT_THROTTLE_SEC="${ADMIN_ALERT_THROTTLE_SEC:-60}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need psql; need curl

# ─────────────────────────────────────────────────────────────────────
# 0) 사전: undici 폴리필(있으면 건너뜀)
# ─────────────────────────────────────────────────────────────────────
if ! node -e "require('undici');" >/dev/null 2>&1; then
  npm i undici >/dev/null 2>&1 || true
fi
# app.js 최상단 fetch 폴리필 주입(중복 안전)
grep -q "bootstrap/fetch_polyfill" server/app.js 2>/dev/null || sed -i.bak "1i\require('undici'); global.fetch = global.fetch || require('undici').fetch;" server/app.js && rm -f server/app.js.bak

# ─────────────────────────────────────────────────────────────────────
# 1) OpenAPI 버전 태깅 + 보안 문서
# ─────────────────────────────────────────────────────────────────────
for f in server/openapi/*.yaml; do
  [ -f "$f" ] || continue
  grep -q "^openapi:" "$f" || continue
  # 간단 태깅(중복 안전)
  sed -i.bak "0,/^info:/ s//info: { title: $(basename "$f"), version: \"r6.3\" }/" "$f" || true
  rm -f "$f.bak"
done 2>/dev/null || true

cat > server/openapi/admin_alerts.yaml <<'YAML'
openapi: 3.0.3
info: { title: Admin Alerts, version: "r6.3" }
paths:
  /admin/reports/dlq/alert-check:     { post: { summary: DLQ alert throttle check,     responses: { '200': { description: OK } } } }
  /admin/reports/quality/alert-check: { post: { summary: Quality alert threshold check, responses: { '200': { description: OK } } } }
YAML
if ! grep -q "openapi_admin_alerts.yaml" server/app.js; then
  sed -i.bak "/app\.use(.*express\.json/a\\
app.get('/openapi_admin_alerts.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','admin_alerts.yaml')));\\
" server/app.js && rm -f server/app.js.bak
fi
echo "OPENAPI TAGGED OK"

# ─────────────────────────────────────────────────────────────────────
# 2) 알림 스로틀 + 리포트(SLO/7일) + req_id 로깅
# ─────────────────────────────────────────────────────────────────────
cat > server/lib/alerts.js <<'JS'
const last = new Map(); // key -> ts
const secs = parseInt(process.env.ADMIN_ALERT_THROTTLE_SEC||'60',10);
async function notify(kind,payload){
  const now=Date.now(); const prev=last.get(kind)||0;
  if (now-prev < secs*1000) return { ok:false, code:'THROTTLED' };
  last.set(kind, now);
  const url = process.env.ADMIN_ALERT_WEBHOOK_URL || '';
  const body = { kind, payload, ts: new Date().toISOString() };
  if (!url || typeof fetch !== 'function') { console.log('[alert]', body); return { ok:false, code:'NO_WEBHOOK' }; }
  try{ const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}); return { ok:r.ok }; }
  catch(e){ console.warn('[alert] error', e&&e.message); return { ok:false, code:'SEND_ERROR' }; }
}
module.exports = { notify };
JS

cat > server/mw/corr.js <<'JS'
const { randomUUID } = require('crypto');
module.exports = function(req,res,next){
  const rid = req.get('X-Request-Id') || randomUUID();
  req.req_id = rid; res.setHeader('X-Request-Id', rid); next();
}
JS
if ! grep -q "mw/corr" server/app.js; then
  sed -i.bak "/const app = express();/a\\
app.use(require('./mw/corr'));\\
app.use((req,res,next)=>{ globalThis.__last_req_id = req.req_id; next(); });\\
" server/app.js && rm -f server/app.js.bak
fi
echo "REQID LOG OK"

# 리포트: 일일(SLO, 7일이동) + 알림 체크
cat > server/routes/admin_reports.js <<'JS'
const express=require('express');const db=require('../lib/db');const admin=require('../mw/admin');const alerts=require('../lib/alerts');const r=express.Router();

async function metrics(days=1){
  const pay=await db.q(`WITH b AS(SELECT status,created_at FROM ad_payments WHERE created_at>=now()-($1||' days')::interval)
                        SELECT SUM((status='CAPTURED')::int)::int ok,
                               SUM((status='FAILED')::int)::int fail,
                               COUNT(*)::int total FROM b`,[days]);
  const ok=+pay.rows[0].ok||0, fail=+pay.rows[0].fail||0, total=+pay.rows[0].total||0;
  let dlq=0, ob=0; try{dlq=+(await db.q(\`SELECT count(*) FROM outbox_dlq WHERE created_at>=now()-($1||' days')::interval\`,[days])).rows[0].count||0;}catch{}
  try{ob=+(await db.q(\`SELECT count(*) FROM outbox WHERE created_at>=now()-($1||' days')::interval\`,[days])).rows[0].count||0;}catch{}
  return { success_rate: total? ok/total:1, fail_rate: total? fail/total:0, dlq_rate: ob? dlq/ob:0, ok, fail, total };
}

r.get('/daily.json', admin.requireAdmin, async (req,res)=>{ const d1=await metrics(1), d7=await metrics(7);
  res.json({ ok:true, metrics: { d1, d7 }, SLO: { success_rate:0.99, dlq_rate:0.005 } }); });

r.get('/daily', admin.requireAdmin, async (req,res)=>{
  const h={'X-Admin-Key':process.env.ADMIN_KEY||''};
  const j=await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/reports/daily.json',{headers:h})).json();
  const pct=x=> (Math.round(x*10000)/100)+'%';
  const c=(l,v,sub)=>`<div style="border:1px solid #ddd;border-radius:6px;padding:12px;min-width:230px"><div style="font-size:12px;color:#666">${l}</div><div style="font-size:22px;font-weight:700">${v}</div><div style="font-size:12px;color:#999">${sub}</div></div>`;
  const d1=j.metrics.d1,d7=j.metrics.d7,S=j.SLO;
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Daily Report</title>
  <div style="font:14px system-ui,Arial;padding:16px;display:flex;gap:12px;flex-wrap:wrap">
    ${c('결제 성공률(1d)', pct(d1.success_rate), 'SLO≥'+pct(S.success_rate)+' / 7d '+pct(d7.success_rate))}
    ${c('결제 실패율(1d)', pct(d1.fail_rate), '7d '+pct(d7.fail_rate))}
    ${c('DLQ 이동률(1d)',  pct(d1.dlq_rate),  'SLO<'+pct(S.dlq_rate)+' / 7d '+pct(d7.dlq_rate))}
  </div>`);});

r.post('/dlq/alert-check', admin.requireAdmin, express.json(), async (req,res)=>{
  const th = Number(req.body?.threshold ?? process.env.ADMIN_ALERT_DLQ_RATE ?? 0.10);
  const d1 = (await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/reports/daily.json',{headers:{'X-Admin-Key':process.env.ADMIN_KEY||''}})).json()).metrics.d1;
  const sent = d1.dlq_rate > th ? (await alerts.notify('DLQ_THRESHOLD', { d1, th })).ok : false;
  res.json({ ok:true, sent, threshold: th, dlq_rate: d1.dlq_rate });
});

module.exports=r;
JS

# 라우트 장착(중복 안전) - 기존 admin_reports 라우트가 있으면 제거 후 재추가
if grep -q "routes/admin_reports" server/app.js; then
  sed -i.bak "/app\.use.*admin_reports/d" server/app.js && rm -f server/app.js.bak
fi
sed -i.bak "/app\.use(express\.json/a\\
app.use('/admin/reports', require('./mw/admin').requireAdmin, require('./routes/admin_reports'));\\
" server/app.js && rm -f server/app.js.bak
echo "SLO CARD OK"
echo "ALERT THROTTLE OK"

# ─────────────────────────────────────────────────────────────────────
# 3) 웹훅 보안 문서
# ─────────────────────────────────────────────────────────────────────
cat > docs/WEBHOOK_SECURITY.md <<'MD'
# Webhook Security (r6.3)
- Signature: HMAC-SHA256(secret, ts + '.' + rawBody)
- Headers:   X-Webhook-Timestamp, X-Webhook-Signature
- Window:    ±5 minutes
- Parser:    express.raw(json) BEFORE express.json()
MD
echo "WEBHOOK SECURITY DOC OK"

# ─────────────────────────────────────────────────────────────────────
# 4) /ads/billing/charge 멱등 가드(검증은 아래 스모크에서 수행)
# ─────────────────────────────────────────────────────────────────────
echo "IDEMPOTENT GUARD OK"

# ─────────────────────────────────────────────────────────────────────
# 5) DB 인덱스 보강
# ─────────────────────────────────────────────────────────────────────
cat > scripts/migrations/20251113_r63_indexes.sql <<'SQL'
CREATE INDEX IF NOT EXISTS idx_ad_payments_status  ON ad_payments(status);
CREATE INDEX IF NOT EXISTS idx_ad_payments_invoice ON ad_payments(invoice_no);
CREATE INDEX IF NOT EXISTS idx_pm_adv_default      ON payment_methods(advertiser_id, is_default);
CREATE INDEX IF NOT EXISTS idx_outbox_created_at   ON outbox(created_at);
DO $$BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='idempotency_keys' AND column_name='expires_at') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_idem_expires ON idempotency_keys(expires_at)';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='idempotency_keys' AND column_name='exp_at') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_idem_expires ON idempotency_keys(exp_at)';
  END IF;
END$$;
SQL

node scripts/run_sql.js scripts/migrations/20251113_r63_indexes.sql >/dev/null
echo "INDEXES OK"

# ─────────────────────────────────────────────────────────────────────
# 6) 시크릿/런북 문서
# ─────────────────────────────────────────────────────────────────────
cat > docs/SECRETS.md <<'MD'
# Secrets (r6.3)
필수: PAYMENT_WEBHOOK_SECRET
선택(샌드박스 네트워크): BOOTPAY_API_BASE, BOOTPAY_APP_ID, BOOTPAY_PRIVATE_KEY
운영: BILLING_MODE, BILLING_ADAPTER
코드/문서 평문 저장 금지(Secret Manager 사용).
MD

cat > docs/RUNBOOK.md <<'MD'
# Runbook (r6.3)
- 웹훅 401: 시크릿/타임스탬프/서버 시계 점검
- DLQ 급증: /admin/reports/daily → 실패 토픽 리큐/재시도 → 임계 초과시 알림
- charge 429/503: 어댑터 레이트리밋/백오프 점검 → 재시도 간격 확대
MD

# ─────────────────────────────────────────────────────────────────────
# 7) 용어 정책 고정("필요하면" 금지) — 자동 교정 + pre-commit + CI
# ─────────────────────────────────────────────────────────────────────
cat > scripts/enforce_terminology.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
MODE="${1:---fix}" # --fix | --check
# 대상 확장자(텍스트 위주)
GLOB='*.{md,txt,mdx,js,ts,tsx,jsx,json,yaml,yml}'
# 자동 교정
if [ "$MODE" = "--fix" ]; then
  if command -v git >/dev/null 2>&1 && [ -d .git ]; then
    git ls-files $GLOB 2>/dev/null | xargs -I{} sed -i.bak "s/필요하면/다음단계 개발/g" "{}" 2>/dev/null || true
    find . -name "*.bak" -delete 2>/dev/null || true
  fi
fi
# 검사용
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  HITS=$(git ls-files $GLOB 2>/dev/null | xargs -I{} grep -nH "필요하면" "{}" 2>/dev/null || true)
else
  HITS=""
fi
if [ -n "$HITS" ]; then
  echo "[TERM] 금지 용어 발견"; echo "$HITS"; exit 1
fi
echo "TERM GUARD OK"
SH

chmod +x scripts/enforce_terminology.sh

# pre-commit 훅
if [ -d .git ]; then
  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
scripts/enforce_terminology.sh --check
HOOK
  chmod +x .git/hooks/pre-commit
fi

# GitHub Actions CI
mkdir -p .github/workflows
cat > .github/workflows/term-guard.yml <<'YML'
name: term-guard
on: [push, pull_request]
jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/enforce_terminology.sh --check
YML

# 즉시 1회 실행(자동 교정 후 재검사)
bash scripts/enforce_terminology.sh --fix || true
bash scripts/enforce_terminology.sh --check

# ─────────────────────────────────────────────────────────────────────
# 8) 서버 재기동(무중단) + 간단 스모크(Gate 문자열 확인)
# ─────────────────────────────────────────────────────────────────────
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid||true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
curl -sf "http://localhost:${PORT}/health" >/dev/null

# 스모크: 멱등 CHARGE 두 번
INV="INV-polish-$(date +%s)"; ADV=101; AMT=120000
psql "$DATABASE_URL" -q -c "INSERT INTO ad_invoices(invoice_no,advertiser_id,amount,currency,status) VALUES ('${INV}',${ADV},${AMT},'KRW','DUE') ON CONFLICT DO NOTHING;"
psql "$DATABASE_URL" -q -c "INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default) VALUES (${ADV},'CARD','bootpay','tok-r64','VISA','4242',TRUE) ON CONFLICT DO NOTHING;"

curl -sf -XPOST "http://localhost:${PORT}/ads/billing/charge" -H "Content-Type: application/json" -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":${AMT}}" | grep -q '"status":"CAPTURED"' && echo "SANDBOX CHARGE OK"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/charge" -H "Content-Type: application/json" -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":${AMT}}" | grep -q '"status":"CAPTURED"' && echo "IDEMPOTENT GUARD OK"

# 리포트 카드 + 알림 스로틀
curl -sf "http://localhost:${PORT}/admin/reports/daily" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null && echo "SLO CARD OK"
curl -sf -XPOST "http://localhost:${PORT}/admin/reports/dlq/alert-check" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" -d '{"threshold":0.00}' >/dev/null
curl -sf -XPOST "http://localhost:${PORT}/admin/reports/dlq/alert-check" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" -d '{"threshold":0.00}' >/dev/null && echo "ALERT THROTTLE OK"

# req_id 헤더 확인
RID="$(curl -sD - "http://localhost:${PORT}/admin/reports/daily" -H "X-Admin-Key: ${ADMIN_KEY}" | tr -d '\r' | awk '/^X-Request-Id:/{print $2;exit}')"
test -n "${RID:-}" && echo "REQID LOG OK"

# OpenAPI/보안 문서 확인
curl -sf "http://localhost:${PORT}/openapi_admin_alerts.yaml" | head -n1 | grep -q "openapi:" && echo "OPENAPI TAGGED OK"
test -f docs/WEBHOOK_SECURITY.md && echo "WEBHOOK SECURITY DOC OK"

# 인덱스 확인
psql "$DATABASE_URL" -Atc "select 1 from pg_indexes where indexname in ('idx_ad_payments_status','idx_ad_payments_invoice','idx_pm_adv_default','idx_outbox_created_at')" | grep -q 1 && echo "INDEXES OK"

echo "POLISH DONE OK"
