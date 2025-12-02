#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"

TS=$(date +%s)
EMAIL="r8_${TS}@example.com"
PASS="Passw0rd!"

echo "[0] signup/login"
curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}" | jq . || curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}"

LOGIN_RESP=$(curl -s -X POST "${BASE}/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
echo "${LOGIN_RESP}" | jq . || echo "${LOGIN_RESP}"
TOKEN=$(echo "${LOGIN_RESP}" | jq -r '.token' 2>/dev/null || echo "")

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
  echo "[ERR] 토큰 추출 실패"
  exit 1
fi

AUTH=(-H "Authorization: Bearer ${TOKEN}")

echo
echo "[1] store & sub & invoice"
STORE_RESP=$(curl -s -X POST "${BASE}/stores" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"r8매장","address":"서울","phone":"010-0000-0000"}')
echo "${STORE_RESP}" | jq . || echo "${STORE_RESP}"
SID=$(echo "${STORE_RESP}" | jq -r '.store.id' 2>/dev/null || echo "")

if [ -z "${SID}" ] || [ "${SID}" = "null" ]; then
  echo "[ERR] 매장 ID 추출 실패"
  exit 1
fi

curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" -d '{"plan_code":"S"}' | jq . || curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" -d '{"plan_code":"S"}'

INV_RESP=$(curl -s -X POST "${BASE}/stores/${SID}/billing/invoices" "${AUTH[@]}")
echo "${INV_RESP}" | jq . || echo "${INV_RESP}"
INV_ID=$(echo "${INV_RESP}" | jq -r '.invoice_id' 2>/dev/null || echo "")

echo
echo "[2] clean campaign -> activate OK"
CAMP_RESP=$(curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"클린","objective":"traffic","daily_budget_krw":10000,"primary_text":"오픈 할인"}')
echo "${CAMP_RESP}" | jq . || echo "${CAMP_RESP}"
CID=$(echo "${CAMP_RESP}" | jq -r '.campaign.id' 2>/dev/null || echo "")

if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

echo
echo "[3] overdue mock -> activate fail (BLOCKED_BY_BILLING)"
curl -s -X POST "${BASE}/dev/stores/${SID}/billing/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"action":"make_overdue"}' | jq . || curl -s -X POST "${BASE}/dev/stores/${SID}/billing/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"action":"make_overdue"}'

if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

echo
echo "[4] PG mock webhook -> invoice paid -> auto resume"
curl -s -X POST "${BASE}/dev/pg/webhook/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d "{\"provider\":\"mock\",\"invoice_id\":${INV_ID},\"amount_krw\":4990,\"type\":\"payment.succeeded\"}" | jq . || curl -s -X POST "${BASE}/dev/pg/webhook/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d "{\"provider\":\"mock\",\"invoice_id\":${INV_ID},\"amount_krw\":4990,\"type\":\"payment.succeeded\"}"

echo
echo "[5] 재활성화 재시도(자동재개가 켜져 있으면 이미 active 가능)"
if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

echo
echo "=== DONE ==="

