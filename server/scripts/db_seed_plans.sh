#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "❌ DATABASE_URL 환경변수가 설정되지 않았습니다."
  exit 1
fi

echo "📦 Plans 시드 데이터 입력 중..."
psql "${DATABASE_URL}" <<'SQL'
INSERT INTO plans (code, name, price, ad_budget, features) VALUES
  ('S', 'Starter', 200000, 120000, ARRAY['페이스북/인스타그램 또는 틱톡 중 택1', '기본 리포트']),
  ('M', 'Standard', 400000, 300000, ARRAY['페이스북/인스타그램 + 틱톡', '고급 리포트']),
  ('L', 'Pro', 800000, 600000, ARRAY['페이스북/인스타그램 + 틱톡', '프리미엄 리포트'])
ON CONFLICT (code) DO NOTHING;
SQL

echo "✅ 시드 데이터 입력 완료"
