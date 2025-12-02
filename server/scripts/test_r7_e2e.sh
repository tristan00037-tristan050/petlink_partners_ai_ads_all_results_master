#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"
ADMIN_KEY="${ADMIN_KEY:-change-admin-key}"

# 신규 계정/매장/구독/인보이스
TS=$(date +%s)
EMAIL="r7_${TS}@example.com"
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
echo "[1] create store & subscribe"
STORE_RESP=$(curl -s -X POST "${BASE}/stores" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"r7 매장","address":"서울","phone":"010-0000-0000"}')
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
echo "[2] create banned campaign -> activate => BLOCKED_BY_POLICY"
CAMP_RESP=$(curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"위반캠페인","objective":"traffic","daily_budget_krw":10000,"primary_text":"무료 당첨 혜택"}')
echo "${CAMP_RESP}" | jq . || echo "${CAMP_RESP}"
CID=$(echo "${CAMP_RESP}" | jq -r '.campaign.id' 2>/dev/null || echo "")

if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

echo
echo "[3] admin resolve policy -> activate OK"
curl -s -X POST "${BASE}/admin/policy/campaigns/${CID}/resolve" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"note":"컨텐츠 수정 승인"}' | jq . || curl -s -X POST "${BASE}/admin/policy/campaigns/${CID}/resolve" -H "X-Admin-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" \
  -d '{"note":"컨텐츠 수정 승인"}'

if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

echo
echo "[4] status map"
curl -s "${BASE}/meta/status-map" | jq . || curl -s "${BASE}/meta/status-map"

echo
echo "[5] notifier/billing scheduler dry-run"
curl -s -X POST "${BASE}/admin/ops/scheduler/run" -H "X-Admin-Key: ${ADMIN_KEY}" | jq . || curl -s -X POST "${BASE}/admin/ops/scheduler/run" -H "X-Admin-Key: ${ADMIN_KEY}"

echo
echo "=== DONE ==="

