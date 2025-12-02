#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ DATABASE_URL 환경변수가 설정되지 않았습니다."
  exit 1
fi

echo "📦 DDL 적용 중..."
psql "${DATABASE_URL}" -f scripts/db_migrate_r41.sql

echo "✅ 마이그레이션 완료"
