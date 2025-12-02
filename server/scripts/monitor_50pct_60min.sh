#!/usr/bin/env bash
# 50% 승격 후 60분 즉시 점검 루틴
# 사용법: ./scripts/monitor_50pct_60min.sh [advertiser_id]
# 예: ./scripts/monitor_50pct_60min.sh 101

set -euo pipefail

export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

AID="${1:-101}"
INTERVAL="${INTERVAL:-600}"  # 10분 (600초)

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "  ✅ $*"; }
warn(){ echo "  ⚠️  $*"; }
fail(){ echo "  ❌ $*"; }

echo "=== 50% 승격 후 60분 즉시 점검 루틴 ==="
echo "광고주 ID: ${AID}"
echo "간격: ${INTERVAL}초 (10분)"
echo "총 6회 실행"
echo ""

# TV 대시 & 가드 (10분 간격×6회 ≈ 1시간)
for i in {1..6}; do
  say "[${i}/6] $(date '+%Y-%m-%d %H:%M:%S') - TV Dash & Guard"
  
  # TV Dash (30분 창)
  echo "  TV Dash (30분 창):"
  TV_RESPONSE=$(curl -sS "${BASE}/admin/tv/ramp/json?minutes=30&advertiser_id=${AID}" "${HDR[@]}" 2>/dev/null || echo '{}')
  
  if command -v jq >/dev/null 2>&1; then
    TOTAL=$(echo "$TV_RESPONSE" | jq -r '.total // 0')
    FAIL_RATE=$(echo "$TV_RESPONSE" | jq -r '.fail_rate // 0')
    LIVE_SHARE=$(echo "$TV_RESPONSE" | jq -r '.live_share // 0')
  elif command -v python3 >/dev/null 2>&1; then
    TOTAL=$(echo "$TV_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total',0))" 2>/dev/null || echo "0")
    FAIL_RATE=$(echo "$TV_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('fail_rate',0))" 2>/dev/null || echo "0")
    LIVE_SHARE=$(echo "$TV_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('live_share',0))" 2>/dev/null || echo "0")
  else
    TOTAL=0
    FAIL_RATE=0
    LIVE_SHARE=0
  fi
  
  echo "    attempts: ${TOTAL}"
  echo "    fail_rate: ${FAIL_RATE}"
  echo "    live_share: ${LIVE_SHARE}"
  
  # Guard 상태
  echo "  Guard 상태:"
  GUARD_RESPONSE=$(curl -sS "${BASE}/admin/prod/live/subs/ramp/guard/status" "${HDR[@]}" 2>/dev/null || echo '{}')
  
  if command -v jq >/dev/null 2>&1; then
    GUARD_PASS=$(echo "$GUARD_RESPONSE" | jq -r '.pass // .ok // false')
  elif command -v python3 >/dev/null 2>&1; then
    GUARD_PASS=$(echo "$GUARD_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('pass') or d.get('ok',False))" 2>/dev/null || echo "false")
  else
    GUARD_PASS="false"
  fi
  
  if [ "$GUARD_PASS" = "true" ] || [ "$GUARD_PASS" = "True" ]; then
    ok "Guard PASS"
  else
    warn "Guard 상태 확인 필요"
  fi
  
  # 임계값 체크
  if awk -v f="${FAIL_RATE}" -v t="0.02" 'BEGIN{exit (f<=t)?0:1}'; then
    ok "Fail% 임계 내 (${FAIL_RATE} ≤ 0.02)"
  else
    warn "Fail% 임계 초과 (${FAIL_RATE} > 0.02)"
  fi
  
  if [ "$i" -lt 6 ]; then
    echo ""
    echo "  다음 체크까지 ${INTERVAL}초 대기..."
    sleep "${INTERVAL}"
  fi
done

say "60분 점검 완료"

