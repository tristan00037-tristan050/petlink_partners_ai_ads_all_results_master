#!/usr/bin/env bash
# 개발 환경용 테스트 데이터 생성 스크립트
# 사용법: ./scripts/generate_test_data.sh [advertiser_id] [count]
# 예: ./scripts/generate_test_data.sh 101 25

set -euo pipefail

export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"

AID="${1:-101}"
COUNT="${2:-25}"  # 기본 25개 (MIN_ATTEMPTS=20을 넘기기 위해)

echo "=== 개발 환경용 테스트 데이터 생성 ==="
echo "광고주 ID: ${AID}"
echo "생성 개수: ${COUNT}"
echo ""

# subs_autoroute_journal 테이블 확인
echo "[1] subs_autoroute_journal 테이블 확인"
TABLE_EXISTS=$(psql "$DATABASE_URL" -tAc "
  SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'subs_autoroute_journal'
  );
" 2>/dev/null || echo "false")

if [ "$TABLE_EXISTS" != "t" ]; then
  echo "[ERR] subs_autoroute_journal 테이블이 존재하지 않습니다"
  echo "      r10.6 이상의 마이그레이션이 필요합니다"
  exit 1
fi

# 광고주 확인
echo "[2] 광고주 확인"
ADV_EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT EXISTS(SELECT 1 FROM advertiser_profile WHERE id=${AID});" 2>/dev/null || echo "false")

if [ "$ADV_EXISTS" != "t" ]; then
  echo "[WARN] 광고주 ${AID}가 존재하지 않습니다"
  echo "      테스트 데이터 생성은 계속 진행되지만, 실제 광고주가 필요할 수 있습니다"
fi

# 테스트 데이터 생성
echo "[3] 테스트 데이터 생성"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
-- 최근 30분간의 테스트 데이터 생성
-- 시간 분산: 최근 30분 내에 고르게 분산
INSERT INTO subs_autoroute_journal (
  advertiser_id,
  invoice_id,
  decided,
  eligible_live,
  percent_live,
  amount,
  outcome,
  message,
  created_at
)
SELECT 
  ${AID} as advertiser_id,
  1000 + (random() * 100)::int as invoice_id,
  CASE WHEN random() < 0.8 THEN 'live' ELSE 'sbx' END as decided,
  CASE WHEN random() < 0.8 THEN true ELSE false END as eligible_live,
  CASE 
    WHEN random() < 0.8 THEN 50
    WHEN random() < 0.9 THEN 25
    ELSE 10
  END::int as percent_live,
  1000 + (random() * 5000)::int as amount,
  CASE 
    WHEN random() < 0.95 THEN 
      CASE WHEN random() < 0.8 THEN 'LIVE_OK' ELSE 'SIM_OK' END
    WHEN random() < 0.98 THEN 'SBX_OK'
    ELSE 
      CASE WHEN random() < 0.5 THEN 'LIVE_FAIL' ELSE 'SIM_FAIL' END
  END as outcome,
  CASE 
    WHEN random() < 0.95 THEN 'OK'
    ELSE 'Error occurred'
  END as message,
  now() - (random() * interval '30 minutes') as created_at
FROM generate_series(1, ${COUNT});
SQL

if [ $? -eq 0 ]; then
  echo "✅ 테스트 데이터 생성 완료"
else
  echo "[ERR] 테스트 데이터 생성 실패"
  exit 1
fi

# 생성된 데이터 확인
echo "[4] 생성된 데이터 확인"
ACTUAL_COUNT=$(psql "$DATABASE_URL" -tAc "
  SELECT COUNT(*) 
  FROM subs_autoroute_journal 
  WHERE advertiser_id=${AID} 
  AND created_at >= now() - interval '30 minutes';
" 2>/dev/null || echo "0")

echo "  최근 30분간 데이터: ${ACTUAL_COUNT}건"

# TV Dash 확인 (선택적)
if command -v curl >/dev/null 2>&1 && [ -n "${ADMIN_KEY:-}" ]; then
  echo "[5] TV Dash 확인 (선택적)"
  PORT="${PORT:-5902}"
  BASE="${BASE:-http://localhost:${PORT}}"
  
  TV_RESPONSE=$(curl -sS "${BASE}/admin/tv/ramp/json?minutes=30&advertiser_id=${AID}" \
    -H "X-Admin-Key: ${ADMIN_KEY:-admin-dev-key-123}" 2>/dev/null || echo '{}')
  
  if command -v jq >/dev/null 2>&1; then
    TOTAL=$(echo "$TV_RESPONSE" | jq -r '.total // 0')
    FAIL_RATE=$(echo "$TV_RESPONSE" | jq -r '.fail_rate // 0')
  elif command -v python3 >/dev/null 2>&1; then
    TOTAL=$(echo "$TV_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total',0))" 2>/dev/null || echo "0")
    FAIL_RATE=$(echo "$TV_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('fail_rate',0))" 2>/dev/null || echo "0")
  else
    TOTAL=0
    FAIL_RATE=0
  fi
  
  echo "  TV Dash total: ${TOTAL}"
  echo "  TV Dash fail_rate: ${FAIL_RATE}"
fi

echo ""
echo "=== 완료 ==="
echo "이제 다음 명령으로 50% 승격을 실행할 수 있습니다:"
echo "  export ADMIN_KEY=\"admin-dev-key-123\""
echo "  export AIDS=\"${AID}\""
echo "  ./scripts/promote_50.sh \"${AID}\""

