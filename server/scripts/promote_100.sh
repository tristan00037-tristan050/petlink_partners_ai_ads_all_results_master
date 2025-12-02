#!/usr/bin/env bash
# 100% 승격 래퍼 스크립트
# 사용법: ./scripts/promote_100.sh [advertiser_ids]
# 예: ./scripts/promote_100.sh "101,102"

set -euo pipefail

export PROMOTE_PERCENT=100
export MIN_ATTEMPTS="${MIN_ATTEMPTS:-80}"  # 100%는 80~120 권장

exec "$(dirname "$0")/promote_50.sh" "${1:-${AIDS:-}}"

