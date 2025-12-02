#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-5902}"

bash scripts/apply_r52_finance.sh
psql "$DATABASE_URL" -f scripts/migrations/20251112_r52.sql

# 재기동
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1

for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; [ "$i" -eq 20 ] && { echo "[ERR] 서버 무응답"; tail -n +200 .petlink.out || true; exit 1; }; done

# 주문 A: capture 후 부분환불 → 전액환불
ORDA="ORDA-$(date +%s)"
curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORDA}\",\"provider_txn_id\":\"tx-${ORDA}\",\"amount\":150000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null

TS="$(date +%s)"; PAY="{\"order_id\":\"${ORDA}\",\"event\":\"CAPTURED\",\"amount\":150000,\"receipt_id\":\"r-${ORDA}\"}"
SIG="$(node -e "const c=require('crypto');const ts=process.argv[1];const s=process.env.PAYMENT_WEBHOOK_SECRET;const p=process.argv[2];process.stdout.write(c.createHmac('sha256',s).update(String(ts)).update('.').update(p).digest('hex'))" "$TS" "$PAY")"

curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" -H "Content-Type: application/json" -H "X-Webhook-Signature: ${SIG}" -H "X-Webhook-Timestamp: ${TS}" --data-binary "$PAY" >/dev/null

# 부분 환불 50,000
curl -sf -XPOST "http://localhost:${PORT}/billing/refund" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORDA}\",\"amount\":50000,\"reason\":\"test-partial\",\"refund_id\":\"RF1-${ORDA}\"}" | grep -q '"ok":true' && echo "REFUND PARTIAL OK"

# 전액 환불(잔액)
curl -sf -XPOST "http://localhost:${PORT}/billing/refund" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORDA}\",\"amount\":100000,\"reason\":\"test-final\",\"refund_id\":\"RF2-${ORDA}\"}" | grep -q '"ok":true' && echo "REFUND FINAL OK"

ST="$(psql "$DATABASE_URL" -Atc "select status,refunded_total from payments where order_id='${ORDA}';")"
echo "$ST" | grep -q "CANCELED" && echo "PAYMENT CANCELED VERIFIED"

# 주문 B: capture 후 정산 스냅샷
ORDB="ORDB-$(date +%s)"
curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORDB}\",\"provider_txn_id\":\"tx-${ORDB}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null

TS2="$(date +%s)"; PAY2="{\"order_id\":\"${ORDB}\",\"event\":\"CAPTURED\",\"amount\":200000,\"receipt_id\":\"r-${ORDB}\"}"
SIG2="$(node -e "const c=require('crypto');const ts=process.argv[1];const s=process.env.PAYMENT_WEBHOOK_SECRET;const p=process.argv[2];process.stdout.write(c.createHmac('sha256',s).update(String(ts)).update('.').update(p).digest('hex'))" "$TS2" "$PAY2")"

curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" -H "Content-Type: application/json" -H "X-Webhook-Signature: ${SIG2}" -H "X-Webhook-Timestamp: ${TS2}" --data-binary "$PAY2" >/dev/null

curl -sf -XPOST "http://localhost:${PORT}/admin/settlements/snapshot" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "SETTLEMENT SNAPSHOT OK"

CNTSET="$(psql "$DATABASE_URL" -Atc "select count(*) from settlements where order_id='${ORDB}';")"; [ "$CNTSET" -ge 1 ] && echo "SETTLEMENT CREATED OK"

# 컴플라이언스
psql "$DATABASE_URL" -c "UPDATE payments SET metadata=jsonb_build_object('card_number','4111111111111111','email','user@example.com') WHERE order_id='${ORDB}'" >/dev/null

curl -sf -XPOST "http://localhost:${PORT}/admin/ops/compliance/sanitize" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true' && echo "COMPLIANCE SANITIZE OK"

CHK="$(psql "$DATABASE_URL" -Atc "select (metadata ? 'card_number')::int from payments where order_id='${ORDB}';")"; [ "$CHK" = "0" ] && echo "PII REDACTED VERIFIED"

echo "r5.2 done"


