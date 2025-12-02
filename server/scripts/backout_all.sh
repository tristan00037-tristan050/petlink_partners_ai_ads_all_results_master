#!/usr/bin/env bash
# 즉시 백아웃(0%) 유틸
# 사용법: ./scripts/backout_all.sh [advertiser_ids] [percent]
# 예: ./scripts/backout_all.sh "101,102" 0

set -euo pipefail

export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

AIDS="${1:-${AIDS:-101}}"
PCT="${2:-0}"

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "$*"; }

say "[Backout] 백아웃 실행: ${PCT}%"

IFS=',' read -r -a AID_ARR <<< "${AIDS}"
for aid in "${AID_ARR[@]}"; do
  curl -sf -XPOST "${BASE}/admin/prod/cutover/backout" "${HDR[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"advertiser_id\":${aid},\"fallback_percent\":${PCT},\"dryrun\":false}" \
    >/dev/null && ok "BACKOUT OK (adv=${aid} -> ${PCT}%)" || echo "[ERR] BACKOUT FAIL (adv=${aid})"
done

say "==== BACKOUT COMPLETE ===="

