#!/usr/bin/env bash
# 50% 승격 사전 점검 스크립트
# 사용법: ./scripts/precheck_50.sh [advertiser_ids]
# 예: ./scripts/precheck_50.sh "101,102"

set -euo pipefail

export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export MIN_ATTEMPTS="${MIN_ATTEMPTS:-20}"
export FAIL_PCT_MAX="${FAIL_PCT_MAX:-0.02}"

AIDS="${1:-${AIDS:-101}}"

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "  ✅ $*"; }
fail(){ echo "  ❌ $*"; return 1; }
warn(){ echo "  ⚠️  $*"; }

say "50% 승격 사전 점검"

# ===== 1. TV Dash 샘플 충족 확인 =====
say "[1] TV Dash 샘플 충족 확인"
IFS=',' read -r -a AID_ARR <<< "${AIDS}"
ALL_OK=0

for aid in "${AID_ARR[@]}"; do
  echo "  광고주 ${aid}:"
  TV_JSON=$(curl -sf "${BASE}/admin/tv/ramp/json?minutes=30&advertiser_id=${aid}" "${HDR[@]}" 2>/dev/null || echo '{}')
  
  if command -v jq >/dev/null 2>&1; then
    TOTAL=$(echo "$TV_JSON" | jq -r '.total // .kpis.total // 0')
    FAIL_RATE=$(echo "$TV_JSON" | jq -r '.fail_rate // .kpis.fail_rate // 0')
  elif command -v python3 >/dev/null 2>&1; then
    TOTAL=$(echo "$TV_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total') or (d.get('kpis') or {}).get('total') or 0)" 2>/dev/null || echo "0")
    FAIL_RATE=$(echo "$TV_JSON" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('fail_rate') or (d.get('kpis') or {}).get('fail_rate') or 0)" 2>/dev/null || echo "0")
  else
    TOTAL=0
    FAIL_RATE=0
  fi
  
  echo "    attempts: ${TOTAL} (최소: ${MIN_ATTEMPTS})"
  echo "    fail_rate: ${FAIL_RATE} (최대: ${FAIL_PCT_MAX})"
  
  if [ "${TOTAL}" -lt "${MIN_ATTEMPTS}" ]; then
    fail "샘플 부족 (${TOTAL} < ${MIN_ATTEMPTS})"
    ALL_OK=1
  else
    ok "샘플 충족"
  fi
  
  if awk -v f="${FAIL_RATE}" -v t="${FAIL_PCT_MAX}" 'BEGIN{exit (f>t)?0:1}'; then
    fail "Fail% 초과 (${FAIL_RATE} > ${FAIL_PCT_MAX})"
    ALL_OK=1
  else
    ok "Fail% 임계 내"
  fi
done

if [ $ALL_OK -ne 0 ]; then
  echo ""
  fail "사전 점검 실패: TV Dash 샘플/임계 조건 미충족"
  exit 1
fi

# ===== 2. 백아웃 루트 검증 (선택적) =====
say "[2] 백아웃 루트 검증 (선택적)"
echo "  백아웃 루트 검증은 테스트 광고주로 수동 수행 권장"
echo "  스크립트: ./scripts/precheck_50_backout_test.sh [test_advertiser_id]"
warn "스킵 (수동 검증 권장)"

say "사전 점검 완료"
ok "모든 조건 충족 - 50% 승격 실행 가능"
echo ""
echo "다음 단계:"
echo "  export ADMIN_KEY=\"your-admin-key\""
echo "  export AIDS=\"${AIDS}\""
echo "  ./scripts/promote_50.sh \"${AIDS}\""

