#!/usr/bin/env bash
# promote_50.sh 실행 래퍼 (경로 자동 설정)
cd "$(dirname "$0")/.." || exit 1
exec ./scripts/promote_50.sh "$@"
