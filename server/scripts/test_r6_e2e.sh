#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"

TS=$(date +%s)
EMAIL="r6_${TS}@example.com"
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
echo "[1] create store"
STORE=$(curl -s -X POST "${BASE}/stores" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"내매장 r6","address":"서울","phone":"010-0000-0000"}')
echo "${STORE}" | jq . || echo "${STORE}"
SID=$(echo "${STORE}" | jq -r '.store.id' 2>/dev/null || echo "")

if [ -z "${SID}" ] || [ "${SID}" = "null" ]; then
  echo "[ERR] 매장 ID 추출 실패"
  exit 1
fi

echo
echo "[2] subscribe plan (S)"
curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"plan_code":"S"}' | jq . || curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"plan_code":"S"}'

echo
echo "[3] billing preview & issue invoice"
curl -s "${BASE}/stores/${SID}/billing/preview" "${AUTH[@]}" | jq . || curl -s "${BASE}/stores/${SID}/billing/preview" "${AUTH[@]}"

INV_RESP=$(curl -s -X POST "${BASE}/stores/${SID}/billing/invoices" "${AUTH[@]}")
echo "${INV_RESP}" | jq . || echo "${INV_RESP}"
INV_ID=$(echo "${INV_RESP}" | jq -r '.invoice_id' 2>/dev/null || echo "")

echo
echo "[4] create campaign with banned words (expected: BLOCKED_BY_POLICY on activate)"
CAMP=$(curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"금칙어 캠페인","objective":"traffic","daily_budget_krw":10000,"primary_text":"무료 당첨 혜택!"}')
echo "${CAMP}" | jq . || echo "${CAMP}"
CID=$(echo "${CAMP}" | jq -r '.campaign.id' 2>/dev/null || echo "")

if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

echo
echo "[5] create clean campaign -> activate OK"
CAMP2=$(curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"클린 캠페인","objective":"traffic","daily_budget_krw":10000,"primary_text":"오픈 기념 할인 진행"}')
echo "${CAMP2}" | jq . || echo "${CAMP2}"
CID2=$(echo "${CAMP2}" | jq -r '.campaign.id' 2>/dev/null || echo "")

if [ -n "${CID2}" ] && [ "${CID2}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID2}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID2}/activate" "${AUTH[@]}"
fi

echo
echo "[6] DEV mock overdue -> expect BLOCKED_BY_BILLING on (re)activate"
curl -s -X POST "${BASE}/dev/stores/${SID}/billing/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"action":"make_overdue"}' | jq . || curl -s -X POST "${BASE}/dev/stores/${SID}/billing/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"action":"make_overdue"}'

if [ -n "${CID2}" ] && [ "${CID2}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID2}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID2}/activate" "${AUTH[@]}"
fi

echo
echo "=== DONE ==="

