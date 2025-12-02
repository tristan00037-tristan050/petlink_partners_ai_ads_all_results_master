#!/usr/bin/env bash
# 10% 승격용 래퍼
# 사용법: ./scripts/promote_to_10.sh [advertiser_ids]
# 예: ./scripts/promote_to_10.sh "101,102"

set -euo pipefail

AIDS="${1:-${AIDS:-101}}"
FAIL_PCT_MAX="${FAIL_PCT_MAX:-0.02}"
MIN_ATTEMPTS="${MIN_ATTEMPTS:-20}"

export FAIL_PCT_MAX MIN_ATTEMPTS

exec "$(dirname "$0")/promote_ramp.sh" "${AIDS}" "10" "5"

