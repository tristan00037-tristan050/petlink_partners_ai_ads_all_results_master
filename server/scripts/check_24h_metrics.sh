#!/usr/bin/env bash
# 24시간 관찰 후 메트릭 수집 스크립트
# 사용법: ./scripts/check_24h_metrics.sh [advertiser_id]
# 예: ./scripts/check_24h_metrics.sh 101

set -euo pipefail

export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

AID="${1:-101}"
PERIOD=$(date +%Y-%m)

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "  ✅ $*"; }
warn(){ echo "  ⚠️  $*"; }

OUTPUT_DIR="evidence/24h_check_${AID}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUTPUT_DIR}"

echo "=== 24시간 관찰 메트릭 수집 ==="
echo "광고주 ID: ${AID}"
echo "출력 디렉토리: ${OUTPUT_DIR}"
echo ""

# 1. TV Dash (30분 창)
say "[1] TV Dash (30분 창)"
TV_RESPONSE=$(curl -sS "${BASE}/admin/tv/ramp/json?minutes=30&advertiser_id=${AID}" "${HDR[@]}" 2>/dev/null || echo '{}')
echo "$TV_RESPONSE" | python3 -m json.tool > "${OUTPUT_DIR}/tv_30m.json" 2>/dev/null || echo "$TV_RESPONSE" > "${OUTPUT_DIR}/tv_30m.json"
echo "$TV_RESPONSE" | python3 -m json.tool
ok "TV Dash 저장: ${OUTPUT_DIR}/tv_30m.json"

# 2. ACK-SLA
say "[2] ACK-SLA"
ACKSLA_RESPONSE=$(curl -sS "${BASE}/admin/reports/pilot/flip/acksla" "${HDR[@]}" 2>/dev/null || echo '{}')
echo "$ACKSLA_RESPONSE" | python3 -m json.tool > "${OUTPUT_DIR}/acksla.json" 2>/dev/null || echo "$ACKSLA_RESPONSE" > "${OUTPUT_DIR}/acksla.json"
echo "$ACKSLA_RESPONSE" | python3 -m json.tool
ok "ACK-SLA 저장: ${OUTPUT_DIR}/acksla.json"

# 3. Preflight
say "[3] Preflight"
PREFLIGHT_RESPONSE=$(curl -sS "${BASE}/admin/prod/preflight" "${HDR[@]}" 2>/dev/null || echo '{}')
echo "$PREFLIGHT_RESPONSE" | python3 -m json.tool > "${OUTPUT_DIR}/preflight.json" 2>/dev/null || echo "$PREFLIGHT_RESPONSE" > "${OUTPUT_DIR}/preflight.json"
echo "$PREFLIGHT_RESPONSE" | python3 -m json.tool
ok "Preflight 저장: ${OUTPUT_DIR}/preflight.json"

# 4. Period×CBK Preview2
say "[4] Period×CBK Preview2 (${PERIOD})"
PERIOD_RESPONSE=$(curl -sS "${BASE}/admin/ledger/periods/preview2?period=${PERIOD}" "${HDR[@]}" 2>/dev/null || echo '{}')
echo "$PERIOD_RESPONSE" | python3 -m json.tool > "${OUTPUT_DIR}/period_preview2.json" 2>/dev/null || echo "$PERIOD_RESPONSE" > "${OUTPUT_DIR}/period_preview2.json"
echo "$PERIOD_RESPONSE" | python3 -m json.tool
ok "Period Preview2 저장: ${OUTPUT_DIR}/period_preview2.json"

# 5. Payout Preview2
say "[5] Payout Preview2 (${PERIOD})"
PAYOUT_RESPONSE=$(curl -sS "${BASE}/admin/ledger/payouts/run/preview2?period=${PERIOD}" "${HDR[@]}" 2>/dev/null || echo '{}')
echo "$PAYOUT_RESPONSE" | python3 -m json.tool > "${OUTPUT_DIR}/payout_preview2.json" 2>/dev/null || echo "$PAYOUT_RESPONSE" > "${OUTPUT_DIR}/payout_preview2.json"
echo "$PAYOUT_RESPONSE" | python3 -m json.tool
ok "Payout Preview2 저장: ${OUTPUT_DIR}/payout_preview2.json"

# 6. CORS 경계 확인
say "[6] CORS 경계 확인"
CORS_HEADERS=$(curl -sSI "${BASE}/admin/prod/rollout/list" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" 2>/dev/null || echo "")
echo "$CORS_HEADERS" | grep -i 'access-control-allow-origin' > "${OUTPUT_DIR}/cors_headers.txt" 2>/dev/null || echo "" > "${OUTPUT_DIR}/cors_headers.txt"
if echo "$CORS_HEADERS" | grep -qi "access-control-allow-origin: ${ADMIN_ORIGIN}"; then
  ok "SPLIT ORIGINS STILL OK (ADMIN)"
else
  warn "CORS 헤더 확인 필요"
fi

# 7. 증빙 폴더 경로 수집
say "[7] 증빙 폴더 경로"
EVID_DIR=$(find evidence -type d -name "ramp_promote_50_*" 2>/dev/null | sort -r | head -1)
if [ -n "$EVID_DIR" ] && [ -d "$EVID_DIR" ]; then
  echo "증빙 폴더: ${EVID_DIR}" > "${OUTPUT_DIR}/evidence_paths.txt"
  ls -1 "${EVID_DIR}" >> "${OUTPUT_DIR}/evidence_paths.txt" 2>/dev/null || true
  ok "증빙 폴더: ${EVID_DIR}"
else
  warn "증빙 폴더를 찾을 수 없습니다"
fi

# 요약 생성
say "[8] 요약 생성"
cat > "${OUTPUT_DIR}/summary.txt" <<EOF
24시간 관찰 메트릭 수집 요약
===============================
수집 시각: $(date '+%Y-%m-%d %H:%M:%S')
광고주 ID: ${AID}
기간: ${PERIOD}
출력 디렉토리: ${OUTPUT_DIR}

수집된 파일:
- tv_30m.json: TV Dash (30분 창)
- acksla.json: ACK-SLA 메트릭
- preflight.json: Preflight 상태
- period_preview2.json: Period×CBK Preview2
- payout_preview2.json: Payout Preview2
- cors_headers.txt: CORS 헤더
- evidence_paths.txt: 증빙 폴더 경로

다음 단계:
1. 위 파일들을 검토하여 루브릭 기준 확인
2. 판단 카드 생성 요청
EOF

cat "${OUTPUT_DIR}/summary.txt"
ok "요약 저장: ${OUTPUT_DIR}/summary.txt"

say "=== 수집 완료 ==="
echo "출력 디렉토리: ${OUTPUT_DIR}"
echo ""
echo "다음 단계:"
echo "  1. ${OUTPUT_DIR} 폴더의 파일들을 검토"
echo "  2. 판단 카드 생성 요청"

