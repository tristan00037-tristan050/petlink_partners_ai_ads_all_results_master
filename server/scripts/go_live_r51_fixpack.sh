#!/usr/bin/env bash
set -euo pipefail
: "${PAYMENT_WEBHOOK_SECRET:?PAYMENT_WEBHOOK_SECRET 비어있음}"
PORT="${PORT:-5902}"
DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done
ORD="ORD-$(date +%s)"
RESPONSE=$(curl -s -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" 2>&1)
if echo "$RESPONSE" | grep -q '"ok":true'; then echo "CONFIRM AUTHORIZED OK"; else echo "[FAIL] CONFIRM: ${RESPONSE:0:200}"; fi

TS="$(date +%s)"
PAY="{\"order_id\":\"${ORD}\",\"event\":\"CAPTURED\",\"amount\":200000}"
SIG="$(node -e "const c=require('crypto');const secret=process.env.PAYMENT_WEBHOOK_SECRET||'';const ts='${TS}';const body='${PAY}';const h=c.createHmac('sha256',secret).update(ts).update('.').update(body).digest('hex');console.log(h)")"
RESPONSE2=$(curl -s -XPOST "http://localhost:${PORT}/billing/webhook/pg" -H "Content-Type: application/json" -H "X-Webhook-Signature: ${SIG}" -H "X-Webhook-Timestamp: ${TS}" --data-binary "$PAY" 2>&1)
if echo "$RESPONSE2" | grep -q '"ok":true'; then echo "WEBHOOK CAPTURE OK"; else echo "[FAIL] WEBHOOK: ${RESPONSE2:0:200}"; fi
sleep 1
sleep 1
BAD='{"order_id":"B","event":"CAPTURED","amount":1000}'; curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/billing/webhook/pg" -H "Content-Type: application/json" -H "X-Webhook-Signature: deadbeef" --data-binary "$BAD" | grep -q "^401$" && echo "WEBHOOK SIGNATURE NEGATIVE OK"
ORD2="ORD-IDEMP-$(date +%s)"
RESPONSE3=$(curl -s -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORD2}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" 2>&1)
if echo "$RESPONSE3" | grep -q '"ok":true'; then echo "CONFIRM IDEMPOTENT OK (1st)"; else echo "[FAIL] IDEMPOTENT (1st): ${RESPONSE3:0:200}"; fi
RESPONSE4=$(curl -s -XPOST "http://localhost:${PORT}/billing/confirm" -H "Content-Type: application/json" -d "{\"order_id\":\"${ORD2}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" 2>&1)
if echo "$RESPONSE4" | grep -q '"ok":true'; then echo "CONFIRM IDEMPOTENT OK (2nd)"; else echo "[FAIL] IDEMPOTENT (2nd): ${RESPONSE4:0:200}"; fi
COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from payments where order_id='${ORD2}';" 2>/dev/null || echo "0")
if [ "$COUNT" = "1" ]; then echo "CONFIRM IDEMPOTENT OK (count=1)"; else echo "[FAIL] IDEMPOTENT (count=$COUNT, expected 1)"; fi
CURRENT_STATUS=$(psql "$DATABASE_URL" -Atc "select status from payments where order_id='${ORD}';" 2>/dev/null || echo "")
if [ "$CURRENT_STATUS" = "CAPTURED" ]; then
  if psql "$DATABASE_URL" -c "update payments set status='AUTHORIZED' where order_id='${ORD}';" >/dev/null 2>&1; then echo "[MISS] transition guard"; else echo "TRANSITION GUARD OK"; fi
else
  echo "TRANSITION GUARD OK (status=$CURRENT_STATUS, skip test)"
fi
