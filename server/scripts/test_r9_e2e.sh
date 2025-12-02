#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"
ADMIN="${ADMIN_KEY:-change-admin-key}"

# 0) 가입/로그인
TS=$(date +%s)
EMAIL="r9_${TS}@example.com"
PASS="Passw0rd!"

echo "[0] signup/login"
curl -s -X POST "${BASE}/auth/signup" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}" >/dev/null

LOGIN_RESP=$(curl -s -X POST "${BASE}/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}")
TOKEN=$(echo "${LOGIN_RESP}" | jq -r '.token' 2>/dev/null || echo "")

if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
  echo "[ERR] 토큰 추출 실패"
  exit 1
fi

AUTH=(-H "Authorization: Bearer ${TOKEN}")

# 1) 매장/구독/인보이스
echo
echo "[1] store & sub & invoice"
STORE_RESP=$(curl -s -X POST "${BASE}/stores" "${AUTH[@]}" -H "Content-Type: application/json" -d '{"name":"r9-store","address":"서울","phone":"010-0000-0000"}')
SID=$(echo "${STORE_RESP}" | jq -r '.store.id' 2>/dev/null || echo "")

if [ -z "${SID}" ] || [ "${SID}" = "null" ]; then
  echo "[ERR] 매장 ID 추출 실패"
  exit 1
fi

curl -s -X POST "${BASE}/stores/${SID}/subscribe" "${AUTH[@]}" -H "Content-Type: application/json" -d '{"plan_code":"S"}' >/dev/null
INV_RESP=$(curl -s -X POST "${BASE}/stores/${SID}/billing/invoices" "${AUTH[@]}")
INV_ID=$(echo "${INV_RESP}" | jq -r '.invoice_id' 2>/dev/null || echo "")

# 2) 연체 → 활성화 시도 실패(BLOCKED_BY_BILLING) 유도
echo
echo "[2] overdue mock -> activate fail (BLOCKED_BY_BILLING)"
curl -s -X POST "${BASE}/dev/stores/${SID}/billing/mock" "${AUTH[@]}" -H "Content-Type: application/json" -d '{"action":"make_overdue"}' >/dev/null || echo "[WARN] mock endpoint disabled"

CAMP_RESP=$(curl -s -X POST "${BASE}/stores/${SID}/campaigns" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d '{"name":"r9 camp","objective":"traffic","daily_budget_krw":10000,"primary_text":"클린 텍스트"}')
CID=$(echo "${CAMP_RESP}" | jq -r '.campaign.id' 2>/dev/null || echo "")

if [ -n "${CID}" ] && [ "${CID}" != "null" ]; then
  curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}" | jq . || curl -s -X POST "${BASE}/campaigns/${CID}/activate" "${AUTH[@]}"
fi

# 3) 결제 Webhook(서명 검증) -> 자동 재개(정밀화)
echo
echo "[3] PG mock webhook -> invoice paid -> auto resume"
curl -s -X POST "${BASE}/dev/pg/webhook/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d "{\"provider\":\"mock\",\"invoice_id\":${INV_ID},\"amount_krw\":4990,\"type\":\"payment.succeeded\"}" | jq . || curl -s -X POST "${BASE}/dev/pg/webhook/mock" "${AUTH[@]}" -H "Content-Type: application/json" \
  -d "{\"provider\":\"mock\",\"invoice_id\":${INV_ID},\"amount_krw\":4990,\"type\":\"payment.succeeded\"}"

# 4) 재처리 워커(멱등) 수동 실행 확인(필요 시)
echo
echo "[4] payment reprocessor (optional)"
./scripts/run_payment_reprocessor.sh 2>&1 | head -5 || echo "[INFO] reprocessor skipped"

# 5) Admin 리포트
echo
echo "[5] admin reports"
curl -s "${BASE}/admin/reports/summary" -H "X-Admin-Key: ${ADMIN}" | jq . || curl -s "${BASE}/admin/reports/summary" -H "X-Admin-Key: ${ADMIN}"
curl -s "${BASE}/admin/reports/billing" -H "X-Admin-Key: ${ADMIN}" | jq . || curl -s "${BASE}/admin/reports/billing" -H "X-Admin-Key: ${ADMIN}"

echo
echo "=== DONE ==="

