#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"

echo "=== [A] Deep Health ==="
curl -s "${BASE}/healthz/deep" | jq . || curl -s "${BASE}/healthz/deep"

echo
echo "=== [B] Signup + Login + Me ==="
TS=$(date +%s)
EMAIL="e2e_${TS}@example.com"
PASS="Passw0rd!"

echo "[1] signup"
curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}" | jq . || curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}"

echo "[2] login"
LOGIN=$(curl -s -X POST "${BASE}/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
echo "${LOGIN}" | jq . || echo "${LOGIN}"
TOKEN=$(echo "${LOGIN}" | jq -r '.token' 2>/dev/null || echo "")

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
  echo "[ERR] 토큰 추출 실패"
  exit 1
fi

echo "[3] me"
curl -s "${BASE}/auth/me" -H "Authorization: Bearer ${TOKEN}" | jq . || curl -s "${BASE}/auth/me" -H "Authorization: Bearer ${TOKEN}"

echo
echo "=== [C] Plans ==="
curl -s "${BASE}/plans" | jq . || curl -s "${BASE}/plans"

echo
echo "=== [D] Metrics ==="
curl -s "${BASE}/metrics" | head -20 || echo "Metrics endpoint 확인"

echo
echo "=== E2E 테스트 완료 ==="

