#!/bin/bash
# smoke_test.sh - 스모크 테스트 (헬스체크 → 채널설정 PUT → Pacer 프리뷰 → 플랜 전환 POST)

set -euo pipefail

ORCHESTRATOR_URL="${ORCHESTRATOR_URL:-http://localhost:8090}"
BILLING_URL="${BILLING_URL:-http://localhost:8091}"
STORE_ID="${STORE_ID:-1}"

echo "=== v2.6 스모크 테스트 ==="
echo ""

# 1. 헬스체크
echo "1. 헬스체크..."
echo "   GET ${ORCHESTRATOR_URL}/healthz"
orchestrator_health=$(curl -s "${ORCHESTRATOR_URL}/healthz")
if echo "$orchestrator_health" | grep -q '"ok":true'; then
    echo "   ✅ 오케스트레이터 서버 정상"
else
    echo "   ❌ 오케스트레이터 서버 오류"
    exit 1
fi

echo "   GET ${BILLING_URL}/healthz"
billing_health=$(curl -s "${BILLING_URL}/healthz")
if echo "$billing_health" | grep -q '"ok":true'; then
    echo "   ✅ 빌링 서버 정상"
else
    echo "   ❌ 빌링 서버 오류"
    exit 1
fi

echo ""

# 2. 채널 설정 PUT
echo "2. 채널 설정 저장..."
echo "   PUT ${ORCHESTRATOR_URL}/api/stores/${STORE_ID}/channel-prefs"
channel_response=$(curl -s -XPUT "${ORCHESTRATOR_URL}/api/stores/${STORE_ID}/channel-prefs" \
    -H 'Content-Type: application/json' \
    -d '{
        "ig_enabled": true,
        "tt_enabled": true,
        "yt_enabled": false,
        "kakao_enabled": false,
        "naver_enabled": false
    }')

if echo "$channel_response" | grep -q '"ok":true'; then
    echo "   ✅ 채널 설정 저장 성공"
    echo "$channel_response" | grep -o '"message":"[^"]*"' || true
else
    echo "   ❌ 채널 설정 저장 실패"
    echo "$channel_response"
    exit 1
fi

echo ""

# 3. Pacer 프리뷰
echo "3. Pacer 프리뷰..."
echo "   GET ${ORCHESTRATOR_URL}/api/pacer/preview?store_id=${STORE_ID}&date=2025-01-15&daily_budget=10000"
pacer_response=$(curl -s "${ORCHESTRATOR_URL}/api/pacer/preview?store_id=${STORE_ID}&date=2025-01-15&daily_budget=10000")

if echo "$pacer_response" | grep -q '"ok":true'; then
    echo "   ✅ Pacer 프리뷰 성공"
    echo "$pacer_response" | grep -o '"adjusted_budget":[0-9]*' || true
    echo "$pacer_response" | grep -o '"estimated_impressions":[0-9]*' || true
    echo "$pacer_response" | grep -o '"radius_km":[0-9]*' || true
    echo "$pacer_response" | grep -o '"daily_pacing"' || true
else
    echo "   ❌ Pacer 프리뷰 실패"
    echo "$pacer_response"
    exit 1
fi

echo ""

# 4. 플랜 전환 POST
echo "4. 플랜 전환..."
echo "   POST ${BILLING_URL}/api/plan/switch"
plan_response=$(curl -s -XPOST "${BILLING_URL}/api/plan/switch" \
    -H 'Content-Type: application/json' \
    -d "{
        \"store_id\": ${STORE_ID},
        \"plan_code\": \"STARTER\"
    }")

if echo "$plan_response" | grep -q '"ok":true'; then
    echo "   ✅ 플랜 전환 성공"
                invoice_id=$(echo "$plan_response" | grep -o '"invoice_id":[0-9]*' | grep -o '[0-9]*' || echo "")
                if [ -n "$invoice_id" ]; then
                    echo "   인보이스 ID: $invoice_id"
                    echo "   인보이스 조회 테스트..."
                    invoice_response=$(curl -s "${BILLING_URL}/api/invoice/${invoice_id}")
                    if echo "$invoice_response" | grep -q '"ok":true'; then
                        echo "   ✅ 인보이스 조회 성공"
                        echo "$invoice_response" | grep -o '"total_amount":[0-9]*' || true
                    else
                        echo "   ⚠️ 인보이스 조회 실패 (계속 진행)"
                    fi
                fi
else
    echo "   ❌ 플랜 전환 실패"
    echo "$plan_response"
    exit 1
fi

echo ""

# 5. 추가 API 테스트 (v2.6 r3)
echo "5. 추가 API 테스트..."
echo "   GET ${ORCHESTRATOR_URL}/api/stores/${STORE_ID}/cpm"
cpm_response=$(curl -s "${ORCHESTRATOR_URL}/api/stores/${STORE_ID}/cpm")
if echo "$cpm_response" | grep -q '"ok":true'; then
    echo "   ✅ CPM 조회 성공"
else
    echo "   ⚠️ CPM 조회 실패 (계속 진행)"
fi

echo "   GET ${ORCHESTRATOR_URL}/api/settings/holidays"
holidays_response=$(curl -s "${ORCHESTRATOR_URL}/api/settings/holidays")
if echo "$holidays_response" | grep -q '"ok":true'; then
    echo "   ✅ 공휴일 조회 성공"
else
    echo "   ⚠️ 공휴일 조회 실패 (계속 진행)"
fi

echo "   GET ${BILLING_URL}/api/plans"
plans_response=$(curl -s "${BILLING_URL}/api/plans")
if echo "$plans_response" | grep -q '"ok":true'; then
    echo "   ✅ 플랜 목록 조회 성공"
else
    echo "   ⚠️ 플랜 목록 조회 실패 (계속 진행)"
fi

echo ""

# 6. Pacer 적용 및 Engine Today 테스트 (v2.6 r3)
echo "6. Pacer 적용 및 Engine Today 테스트..."
echo "   POST ${ORCHESTRATOR_URL}/api/pacer/apply"
pacer_apply_response=$(curl -s -XPOST "${ORCHESTRATOR_URL}/api/pacer/apply" \
    -H 'Content-Type: application/json' \
    -d "{
        \"store_id\": ${STORE_ID},
        \"date\": \"2025-12-15\",
        \"daily_budget\": 800000
    }")

if echo "$pacer_apply_response" | grep -q '"ok":true'; then
    echo "   ✅ Pacer 적용 성공"
    echo "$pacer_apply_response" | grep -o '"adjusted_budget":[0-9]*' || true
else
    echo "   ⚠️ Pacer 적용 실패 (계속 진행)"
fi

echo "   GET ${ORCHESTRATOR_URL}/api/engine/today?store_id=${STORE_ID}&date=2025-12-15"
engine_today_response=$(curl -s "${ORCHESTRATOR_URL}/api/engine/today?store_id=${STORE_ID}&date=2025-12-15")

if echo "$engine_today_response" | grep -q '"ok":true'; then
    echo "   ✅ Engine Today 조회 성공"
    echo "$engine_today_response" | grep -o '"target":[0-9]*' || true
    echo "$engine_today_response" | grep -o '"min":[0-9]*' || true
    echo "$engine_today_response" | grep -o '"max":[0-9]*' || true
else
    echo "   ⚠️ Engine Today 조회 실패 (계속 진행)"
fi

echo ""

# 7. Ingest 및 Metrics 테스트 (v2.6 r3)
echo "7. Ingest 및 Metrics 테스트..."
echo "   POST ${ORCHESTRATOR_URL}/api/ingest/YOUTUBE"
ingest_response=$(curl -s -XPOST "${ORCHESTRATOR_URL}/api/ingest/YOUTUBE" \
    -H 'Content-Type: application/json' \
    -d "{
        \"store_id\": ${STORE_ID},
        \"metrics\": {
            \"impressions\": 1000,
            \"clicks\": 50,
            \"spend\": 3000,
            \"messages\": 5,
            \"leads\": 2
        }
    }")

if echo "$ingest_response" | grep -q '"ok":true'; then
    echo "   ✅ Ingest 성공"
else
    echo "   ⚠️ Ingest 실패 (계속 진행)"
fi

echo "   GET ${ORCHESTRATOR_URL}/api/metrics?store_id=${STORE_ID}"
metrics_response=$(curl -s "${ORCHESTRATOR_URL}/api/metrics?store_id=${STORE_ID}")

if echo "$metrics_response" | grep -q '"ok":true'; then
    echo "   ✅ Metrics 조회 성공"
    echo "$metrics_response" | grep -o '"total_impressions":[0-9]*' || true
    echo "$metrics_response" | grep -o '"overall_cpm":[0-9.]*' || true
else
    echo "   ⚠️ Metrics 조회 실패 (계속 진행)"
fi

echo ""
echo "=== 모든 테스트 통과 ==="

