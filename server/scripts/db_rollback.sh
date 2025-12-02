#!/usr/bin/env bash
# db_rollback.sh - DB 롤백 (선택)

set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL 필수}"

echo "⚠️  롤백 스크립트는 수동으로 작성해야 합니다."
echo "롤백하려면:"
echo "  psql \"\$DATABASE_URL\" -c \"DROP TABLE IF EXISTS ...\""
echo ""
echo "주의: 운영 환경에서는 롤백 전 백업 필수!"


