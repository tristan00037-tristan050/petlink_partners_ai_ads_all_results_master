#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE_URL:-http://localhost:5903}"
jar="$(mktemp)"

# 0) 로그인 → 쿠키 획득
EMAIL="r10_$(date +%s)@example.com"
PASS="Passw0rd!"

echo "[0] signup"
curl -s -X POST "${BASE}/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\",\"tenant\":\"default\"}" >/dev/null

echo "[1] bff/login -> cookie"
curl -s -c "$jar" -b "$jar" -X POST "${BASE}/bff/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASS}\"}" | jq '.ok'

# 2) /bff/me (Authorization 없이 쿠키로 인증)
echo "[2] bff/me (cookie auth)"
curl -s -c "$jar" -b "$jar" "${BASE}/bff/me" | jq '.ok,.user.email'

# 3) /stores (쿠키→Authorization 브릿지 확인)
echo "[3] /stores (cookie bridge)"
curl -s -c "$jar" -b "$jar" "${BASE}/stores" | jq '.ok'

# 4) 로그아웃
echo "[4] bff/logout"
curl -s -c "$jar" -b "$jar" -X POST "${BASE}/bff/logout" | jq '.ok'

# 5) 로그아웃 후 접근 시도 (실패 확인)
echo "[5] logout 후 /bff/me (should fail)"
curl -s -c "$jar" -b "$jar" "${BASE}/bff/me" | jq '.ok,.code'

rm -f "$jar"
echo "=== DONE ==="

