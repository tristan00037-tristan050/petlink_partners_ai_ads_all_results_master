#!/usr/bin/env bash
# 백아웃 루트 검증 스크립트 (테스트 광고주용)
# 사용법: ./scripts/precheck_50_backout_test.sh [test_advertiser_id]
# 예: ./scripts/precheck_50_backout_test.sh 999

set -euo pipefail

export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

TEST_AID="${1:-999}"

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "  ✅ $*"; }
fail(){ echo "  ❌ $*"; exit 1; }

say "백아웃 루트 검증 (테스트 광고주: ${TEST_AID})"

# 1. 25% 설정
say "[1] 25% 설정"
curl -sf -XPOST "${BASE}/admin/prod/cutover/apply" "${HDR[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"advertiser_id\":${TEST_AID},\"percent\":25,\"dryrun\":false}" \
  >/dev/null && ok "25% 설정 완료" || fail "25% 설정 실패"

sleep 2

# 2. 50% 승격
say "[2] 50% 승격"
curl -sf -XPOST "${BASE}/admin/prod/cutover/apply" "${HDR[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"advertiser_id\":${TEST_AID},\"percent\":50,\"dryrun\":false}" \
  >/dev/null && ok "50% 승격 완료" || fail "50% 승격 실패"

sleep 2

# 3. 25% 백아웃
say "[3] 25% 백아웃"
curl -sf -XPOST "${BASE}/admin/prod/cutover/backout" "${HDR[@]}" \
  -H "Content-Type: application/json" \
  -d "{\"advertiser_id\":${TEST_AID},\"fallback_percent\":25,\"dryrun\":false}" \
  >/dev/null && ok "25% 백아웃 완료" || fail "25% 백아웃 실패"

sleep 2

# 4. 최종 확인
say "[4] 최종 확인"
POLICY=$(curl -sf "${BASE}/admin/prod/live/subs/policy?advertiser_id=${TEST_AID}" "${HDR[@]}" 2>/dev/null || echo '{}')

if command -v jq >/dev/null 2>&1; then
  PCT=$(echo "$POLICY" | jq -r '.policy.percent_live // 0')
elif command -v python3 >/dev/null 2>&1; then
  PCT=$(echo "$POLICY" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('policy',{}).get('percent_live',0))" 2>/dev/null || echo "0")
else
  PCT=0
fi

echo "  최종 percent_live: ${PCT}%"

if [ "${PCT}" = "25" ]; then
  ok "백아웃 루트 검증 완료"
  say "==== 백아웃 루트 검증 성공 ===="
else
  fail "백아웃 루트 검증 실패 (예상: 25%, 실제: ${PCT}%)"
fi

