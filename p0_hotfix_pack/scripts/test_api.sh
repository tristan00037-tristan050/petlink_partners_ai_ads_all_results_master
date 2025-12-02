#!/bin/bash
# P0 API 테스트 스크립트
# 스텁 서버 동작 검증

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3800}"

echo "=== P0 API 테스트 ==="
echo ""

echo "[1] Health Check"
curl -s "${BASE_URL}/health" | jq . 2>/dev/null || curl -s "${BASE_URL}/health"
echo ""
echo ""

echo "[2] Plans API"
curl -s "${BASE_URL}/plans" | jq . 2>/dev/null || curl -s "${BASE_URL}/plans"
echo ""
echo ""

echo "[3] Auth Signup (테스트)"
curl -s -X POST "${BASE_URL}/auth/signup" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' | jq . 2>/dev/null || curl -s -X POST "${BASE_URL}/auth/signup" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'
echo ""
echo ""

echo "[4] Campaign Guard (STORE_PROFILE_INCOMPLETE 시뮬레이션)"
curl -s -X POST "${BASE_URL}/campaigns" \
  -H "Content-Type: application/json" \
  -d '{"title":"테스트"}' | jq . 2>/dev/null || curl -s -X POST "${BASE_URL}/campaigns" \
  -H "Content-Type: application/json" \
  -d '{"title":"테스트"}'
echo ""
echo ""

echo "=== 테스트 완료 ==="

