#!/usr/bin/env bash
# Go-Live 테스트 스크립트 (dryrun 모드)
# 사용법: ./scripts/golive_test.sh

set -euo pipefail

export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

echo "═══════════════════════════════════════════════════════════════"
echo "Go-Live 사전 테스트 (Dryrun)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. 서버 상태 확인
echo "[1] 서버 상태 확인..."
if curl -sf "${BASE}/health" >/dev/null 2>&1; then
  echo "  ✅ 서버 실행 중"
else
  echo "  ❌ 서버 미실행"
  exit 1
fi

# 2. Checklist 확인
echo "[2] Go-Live Checklist 확인..."
CHECKLIST=$(curl -sf "${BASE}/admin/prod/golive/checklist" "${HDR[@]}" 2>/dev/null || echo '{"ok":false}')
if echo "$CHECKLIST" | grep -q '"ok":true'; then
  echo "  ✅ Checklist OK"
else
  echo "  ⚠️  Checklist: $(echo "$CHECKLIST" | grep -o '"ok":[^,}]*' || echo 'unknown')"
fi

# 3. Preflight 확인
echo "[3] Preflight 확인..."
PREFLIGHT=$(curl -sf "${BASE}/admin/prod/preflight" "${HDR[@]}" 2>/dev/null || echo '{"ok":false}')
if echo "$PREFLIGHT" | grep -q '"pass":true'; then
  echo "  ✅ Preflight OK"
else
  echo "  ⚠️  Preflight: $(echo "$PREFLIGHT" | grep -o '"pass":[^,}]*' || echo 'unknown')"
fi

# 4. ACK-SLA 확인
echo "[4] ACK-SLA 확인..."
ACKSLA=$(curl -sf "${BASE}/admin/reports/pilot/flip/acksla" "${HDR[@]}" 2>/dev/null || echo '{"ok":false}')
if echo "$ACKSLA" | grep -q '"pass":true'; then
  echo "  ✅ ACK-SLA OK"
else
  echo "  ⚠️  ACK-SLA: $(echo "$ACKSLA" | grep -o '"pass":[^,}]*' || echo 'unknown')"
fi

# 5. TV Dash 확인
echo "[5] TV Dash 확인..."
TV=$(curl -sf "${BASE}/admin/tv/ramp/json?minutes=15&advertiser_id=0" "${HDR[@]}" 2>/dev/null || echo '{"ok":false}')
if echo "$TV" | grep -q '"ok":true'; then
  TOTAL=$(echo "$TV" | grep -o '"total":[0-9]*' | grep -o '[0-9]*' || echo "0")
  FAIL_RATE=$(echo "$TV" | grep -o '"fail_rate":[0-9.]*' | grep -o '[0-9.]*' || echo "0")
  echo "  ✅ TV Dash OK (total: ${TOTAL}, fail_rate: ${FAIL_RATE})"
else
  echo "  ⚠️  TV Dash: 응답 없음"
fi

# 6. 환경 변수 확인
echo "[6] 환경 변수 확인..."
echo "  ADMIN_KEY: ${ADMIN_KEY:0:10}..."
echo "  PORT: ${PORT}"
echo "  BASE: ${BASE}"
echo "  ADMIN_ORIGIN: ${ADMIN_ORIGIN}"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "테스트 완료"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Go-Live 실행:"
echo "  ./scripts/golive.sh [advertiser_ids] [fail_pct_max]"
echo ""
echo "예시:"
echo "  ./scripts/golive.sh \"101\" 0.02"
echo "  ./scripts/golive.sh \"101,102\" 0.02"

