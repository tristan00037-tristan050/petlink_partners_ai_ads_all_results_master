#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"

echo "=== Domain E2E ==="

# 0) 로그인 토큰 준비(신규 가입 후 로그인)
TS=$(date +%s)
EMAIL="store_${TS}@example.com"
PASS="Passw0rd!"

echo "[0-1] signup"
curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}" | jq . || curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}"

echo "[0-2] login"
LOGIN_RESP=$(curl -s -X POST "${BASE}/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
echo "${LOGIN_RESP}" | jq . || echo "${LOGIN_RESP}"
TOKEN=$(echo "${LOGIN_RESP}" | jq -r '.token' 2>/dev/null || echo "")

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
  echo "[ERR] 토큰 추출 실패"
  exit 1
fi

echo "TOKEN=${TOKEN:0:20}..."

AUTH=(-H "Authorization: Bearer ${TOKEN}")

echo
echo "[1] create store"
STORE=$(curl -s -X POST "${BASE}/stores" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"내분양매장","address":"서울시 어딘가","phone":"010-0000-0000"}')
echo "${STORE}" | jq . || echo "${STORE}"
SID=$(echo "${STORE}" | jq -r '.store.id' 2>/dev/null || echo "")

if [ -z "${SID}" ] || [ "${SID}" = "null" ]; then
  echo "[ERR] 매장 ID 추출 실패"
  exit 1
fi

echo
echo "[2] subscribe (S 플랜)"
curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"plan_code":"S"}' | jq . || curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"plan_code":"S"}'

echo
echo "[3] add pet"
curl -s -X POST "${BASE}/stores/${SID}/pets" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"콩이","species":"dog","breed":"푸들","age_months":6,"sex":"F"}' | jq . || curl -s -X POST "${BASE}/stores/${SID}/pets" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"콩이","species":"dog","breed":"푸들","age_months":6,"sex":"F"}'

echo
echo "[4] list pets"
curl -s "${BASE}/stores/${SID}/pets" "${AUTH[@]}" | jq . || curl -s "${BASE}/stores/${SID}/pets" "${AUTH[@]}"

echo
echo "[5] create campaign (policy check - 금칙어 없음)"
curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"오픈기념 이벤트","objective":"traffic","daily_budget_krw":10000,"primary_text":"오픈 기념 혜택!"}' | jq . || curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"오픈기념 이벤트","objective":"traffic","daily_budget_krw":10000,"primary_text":"오픈 기념 혜택!"}'

echo
echo "[6] create campaign (policy check - 금칙어 포함)"
curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"무료 이벤트","objective":"traffic","daily_budget_krw":10000,"primary_text":"무료 당첨 혜택!"}' | jq . || curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"무료 이벤트","objective":"traffic","daily_budget_krw":10000,"primary_text":"무료 당첨 혜택!"}'

echo
echo "[7] list campaigns"
curl -s "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" | jq . || curl -s "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}"

echo
echo "=== DONE ==="

