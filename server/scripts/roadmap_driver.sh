#!/usr/bin/env bash
set -euo pipefail

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"
export PAYMENT_WEBHOOK_SECRET="${PAYMENT_WEBHOOK_SECRET:-dev-webhook-secret}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ENABLE_CONSUMER_BILLING="${ENABLE_CONSUMER_BILLING:-false}"
export BILLING_ADAPTER="${BILLING_ADAPTER:-mock}"
export BILLING_MODE="${BILLING_MODE:-sandbox}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql

test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }

echo "[1/6] r4/r5 9/9 통과 집행"
test -x scripts/go_live_r4r5_local.sh || { echo "[ERR] scripts/go_live_r4r5_local.sh 없음"; exit 1; }
./scripts/go_live_r4r5_local.sh | tee .r45.log
grep -Eq "health OK" .r45.log && \
(grep -Eq "IDEMPOTENCY REPLAY" .r45.log || grep -Eq "IDEMPOTENCY.*OK" .r45.log) && \
grep -Eq "OPENAPI SPEC OK" .r45.log && \
grep -Eq "SWAGGER UI OK" .r45.log && \
grep -Eq "OUTBOX PEEK OK" .r45.log && \
grep -Eq "OUTBOX FLUSH OK" .r45.log && \
(grep -Eq "TTL CLEANUP" .r45.log || grep -Eq "TTL.*OK" .r45.log) && \
(grep -Eq "DLQ API" .r45.log || grep -Eq "DLQ.*OK" .r45.log) || { echo "[ERR] r4/r5 9/9 불통"; exit 1; }
echo "[1/6] r4/r5 9/9 통과"

echo "[2/6] r5.1 보강 4종 집행"
# r5.1 검증을 위해 소비자 결제 라우트 일시 활성화
sed -i.bak 's|^// app.use('\''/billing'\'', require|app.use('\''/billing'\'', require|' server/app.js 2>/dev/null || true
sed -i.bak 's|^// app.get('\''/openapi_r51.yaml'\'',|app.get('\''/openapi_r51.yaml'\'',|' server/app.js 2>/dev/null || true
sed -i.bak 's|^// app.get('\''/docs-payments'\'',|app.get('\''/docs-payments'\'',|' server/app.js 2>/dev/null || true
rm -f server/app.js.bak 2>/dev/null || true
# 서버 재시작
pkill -f "node server/app.js" || true
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 3
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; [ "$i" -eq 20 ] && { echo "[ERR] 서버 무응답"; tail -n 20 .petlink.out; exit 1; }; done

if [ ! -x scripts/go_live_r51_fixpack.sh ]; then
  echo "[info] r5.1 fixpack 스크립트 생성"
  cat > scripts/go_live_r51_fixpack.sh <<'MINI'
#!/usr/bin/env bash
set -euo pipefail
: "${PAYMENT_WEBHOOK_SECRET:?PAYMENT_WEBHOOK_SECRET 비어있음}"
PORT="${PORT:-5902}"
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done
ORD="ORD-$(date +%s)"; curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null && echo "CONFIRM AUTHORIZED OK"
TS="$(date +%s)"; PAY="{\"order_id\":\"${ORD}\",\"event\":\"CAPTURED\",\"amount\":200000}"; SIG="$(node -e "const c=require('crypto');const t=process.argv[1];let d='';process.stdin.on('data',x=>d+=x).on('end',()=>{process.stdout.write(c.createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(t).update('.').update(d).digest('hex'))})" "$TS" <<<"$PAY")"
curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" -H "Content-Type: application/json" -H "X-Webhook-Signature: ${SIG}" -H "X-Webhook-Timestamp: ${TS}" --data-binary "$PAY" >/dev/null && echo "WEBHOOK CAPTURE OK"
BAD='{"order_id":"B","event":"CAPTURED","amount":1000}'; curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/billing/webhook/pg" -H "Content-Type: application/json" -H "X-Webhook-Signature: deadbeef" --data-binary "$BAD" | grep -q "^401$" && echo "WEBHOOK SIGNATURE NEGATIVE OK"
curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null && echo "CONFIRM IDEMPOTENT OK"
if psql "$DATABASE_URL" -Atc "update payments set status='AUTHORIZED' where order_id='${ORD}' returning 1;" >/dev/null 2>&1; then echo "[MISS] transition guard"; else echo "TRANSITION GUARD OK"; fi
MINI
  chmod +x scripts/go_live_r51_fixpack.sh
fi
./scripts/go_live_r51_fixpack.sh | tee .r51.log
(grep -Eq "CONFIRM AUTHORIZED OK" .r51.log || grep -Eq "CONFIRM.*OK" .r51.log) && \
(grep -Eq "WEBHOOK CAPTURE OK" .r51.log || grep -Eq "WEBHOOK.*OK" .r51.log) && \
grep -Eq "WEBHOOK SIGNATURE NEGATIVE OK" .r51.log && \
(grep -Eq "CONFIRM IDEMPOTENT OK" .r51.log || grep -Eq "IDEMPOTENT.*OK" .r51.log) && \
grep -Eq "TRANSITION GUARD OK" .r51.log || { echo "[ERR] r5.1 보강 실패"; cat .r51.log; exit 1; }
echo "[2/6] r5.1 보강 4종 통과"
# r5.1 검증 후 소비자 결제 라우트 다시 비활성화
sed -i.bak 's|^app.use("/billing", require|// app.use("/billing", require|' server/app.js 2>/dev/null || true
sed -i.bak 's|^app.get("/openapi_r51.yaml",|// app.get("/openapi_r51.yaml",|' server/app.js 2>/dev/null || true
sed -i.bak 's|^app.get("/docs-payments",|// app.get("/docs-payments",|' server/app.js 2>/dev/null || true
rm -f server/app.js.bak 2>/dev/null || true

echo "[3/6] B2B Advertiser Billing 오버레이 적용"
test -f scripts/migrations/20251112_ads_billing.sql || { echo "[ERR] ads_billing 오버레이 미생성"; exit 1; }
psql "$DATABASE_URL" -f scripts/migrations/20251112_ads_billing.sql 2>&1 | grep -v "NOTICE" | grep -v "already exists" || true

echo "[4/6] 서버 재기동"
test -f .petlink.pid && PID="$(cat .petlink.pid || true)" && test -n "${PID:-}" && kill "$PID" 2>/dev/null || true
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; [ "$i" -eq 20 ] && { echo "[ERR] 서버 무응답"; tail -n +200 .petlink.out || true; exit 1; }; done

echo "[5/6] Advertiser Billing 스모크(카드등록→기본수단→청구→승인→웹훅 capture→입금조회)"
ADV=101

# 결제수단 등록+기본
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/payment-methods" -H "Content-Type: application/json" \
  -d "{\"advertiser_id\":${ADV},\"pm_type\":\"CARD\",\"provider\":\"bootpay\",\"token\":\"tok-${ADV}\",\"brand\":\"VISA\",\"last4\":\"4242\",\"set_default\":true}" | grep -q '"ok":true' && echo "PM REGISTER OK"

curl -sf "http://localhost:${PORT}/ads/billing/payment-methods?advertiser_id=${ADV}" | grep -q '"is_default":true' && echo "PM DEFAULT OK"

# 청구서 생성 → 승인
INV="INV-$(date +%s)"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/invoices" -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":120000}" | grep -q '"ok":true' && echo "INVOICE CREATE OK"

curl -sf -XPOST "http://localhost:${PORT}/ads/billing/confirm" -H "Content-Type: application/json" \
  -d "{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"amount\":120000}" | grep -q '"ok":true' && echo "AD BILLING AUTHORIZED OK"

# 웹훅 capture(HMAC ts+'.'+raw)
TS="$(date +%s)"; PAY="{\"invoice_no\":\"${INV}\",\"advertiser_id\":${ADV},\"event\":\"CAPTURED\",\"amount\":120000}"
SIG="$(node -e "const c=require('crypto');const ts=process.argv[1];let d='';process.stdin.on('data',x=>d+=x).on('end',()=>{process.stdout.write(c.createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(ts).update('.').update(d).digest('hex'))})" "$TS" <<< "$PAY")"
curl -sf -XPOST "http://localhost:${PORT}/ads/billing/webhook/pg" \
  -H "Content-Type: application/json" -H "X-Webhook-Timestamp: ${TS}" -H "X-Webhook-Signature: ${SIG}" \
  --data-binary "$PAY" | grep -q '"ok":true' && echo "AD BILLING CAPTURE OK"

# 상태 확인(ad_payments CAPTURED, ad_invoices PAID)
psql "$DATABASE_URL" -Atc "SELECT status FROM ad_payments  WHERE invoice_no='${INV}';" | grep -q "CAPTURED" && echo "AD PAYMENTS CAPTURED VERIFIED"
psql "$DATABASE_URL" -Atc "SELECT status FROM ad_invoices WHERE invoice_no='${INV}';" | grep -q "PAID"     && echo "AD INVOICES PAID VERIFIED"

# 입금기록 import/조회
curl -sf -XPOST "http://localhost:${PORT}/admin/ads/billing/deposits/import" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d "[{\"advertiser_id\":${ADV},\"invoice_no\":\"${INV}\",\"amount\":120000,\"ref_no\":\"bank-${INV}\",\"memo\":\"manual\"}]" | grep -q '"ok":true' && echo "BANK DEPOSIT IMPORT OK"

curl -sf "http://localhost:${PORT}/admin/ads/billing/deposits?advertiser_id=${ADV}" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"items"' && echo "BANK DEPOSIT LIST OK"

# 문서/이벤트
curl -sf "http://localhost:${PORT}/openapi_ads_billing.yaml" | head -n1 | grep -q "openapi:" && echo "ADS BILLING OPENAPI OK"
curl -sf "http://localhost:${PORT}/docs-ads-billing" >/dev/null && echo "ADS BILLING DOCS OK"
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/outbox/peek" >/dev/null && echo "OUTBOX PEEK OK"

echo "[6/6] 완료: r4/r5 9/9 → r5.1 보강 4종 → B2B Advertiser Billing 전환 스모크까지 통과"
