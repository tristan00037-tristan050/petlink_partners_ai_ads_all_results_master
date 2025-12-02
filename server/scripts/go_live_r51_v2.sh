#!/usr/bin/env bash
set -euo pipefail

: "${PAYMENT_WEBHOOK_SECRET:?PAYMENT_WEBHOOK_SECRET 비어있음}"
PORT="${PORT:-5902}"

echo "[1/8] r5.1v2 패치 적용"
bash scripts/apply_r51_payments_v2.sh

echo "[2/8] r5.1 스키마 + 보강 스키마 적용"
[ -f scripts/migrations/20251112_r51.sql ] && psql "$DATABASE_URL" -f scripts/migrations/20251112_r51.sql || true
psql "$DATABASE_URL" -f scripts/migrations/20251112_r51_v2.sql

echo "[3/8] 서버 재기동"
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1

echo "[4/8] 헬스체크"
for i in $(seq 1 20); do
  curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }
  sleep 0.3
  [ "$i" -eq 20 ] && { echo "[ERR] 서버 무응답"; tail -n +200 .petlink.out || true; exit 1; }
done

echo "[5/8] 결제 확정(confirm) + 웹훅 시뮬레이션(capture)"
ORD="ORD-$(date +%s)"
curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\":\"${ORD}\",\"provider_txn_id\":\"tx-${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" | grep -q '"ok":true' && echo "CONFIRM AUTHORIZED OK"

TS="$(date +%s)"
PAYLOAD="{\"order_id\":\"${ORD}\",\"event\":\"CAPTURED\",\"amount\":200000,\"receipt_id\":\"receipt-${ORD}\"}"
SIG="$(node -e "const c=require('crypto');const s=process.env.PAYMENT_WEBHOOK_SECRET;const p=process.argv[1];const t=process.argv[2];process.stdout.write(c.createHmac('sha256',s).update(String(t)).update('.').update(p).digest('hex'))" "$PAYLOAD" "$TS")"
curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Signature: ${SIG}" \
  -H "X-Webhook-Timestamp: ${TS}" \
  --data-binary "$PAYLOAD" | grep -q '"ok":true' && echo "WEBHOOK CAPTURE OK"

ST="$(psql "$DATABASE_URL" -Atc "select status from payments where order_id='${ORD}';")"
[ "$ST" = "CAPTURED" ] && echo "PAYMENT CAPTURED VERIFIED" || echo "[WARN] 상태=$ST"

echo "[6/8] 네거티브/멱등/전이 가드"
# 6-1) 시그니처 실패(401 기대)
BADPAY='{"order_id":"TEST-BAD","event":"CAPTURED","amount":1000}'
code="$(curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
  -H "Content-Type: application/json" -H "X-Webhook-Signature: deadbeef" -H "X-Webhook-Timestamp: 0" \
  --data-binary "$BADPAY")"
[ "$code" = "401" ] && echo "WEBHOOK SIGNATURE NEGATIVE OK" || echo "[MISS] webhook 401"

# 6-2) confirm 멱등(order_id 중복 생성 금지)
curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\":\"${ORD}\",\"provider_txn_id\":\"tx-${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null
CNT="$(psql "$DATABASE_URL" -Atc "select count(*) from payments where order_id='${ORD}';")"
[ "$CNT" = "1" ] && echo "CONFIRM IDEMPOTENT OK" || echo "[MISS] confirm idempotency"

# 6-3) 전이 불가(CAPTURED → AUTHORIZED 다운그레이드 차단)
RES="$(psql "$DATABASE_URL" -Atc "update payments set status='AUTHORIZED' where order_id='${ORD}' returning 1;" 2>/dev/null || true)"
[ -z "$RES" ] && echo "TRANSITION GUARD OK" || echo "[MISS] transition guard"

echo "[7/8] 문서/운영 경로 확인"
curl -sf "http://localhost:${PORT}/openapi_r51.yaml" | head -n1 | grep -q "openapi:" && echo "PAYMENTS OPENAPI OK"
curl -sf "http://localhost:${PORT}/docs-payments" >/dev/null && echo "PAYMENTS DOCS OK"
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/outbox/peek" >/dev/null && echo "OUTBOX PEEK OK"

echo "[8/8] 완료"
echo "로그: tail -f .petlink.out"
echo "Outbox: tail -f .outbox.log"
