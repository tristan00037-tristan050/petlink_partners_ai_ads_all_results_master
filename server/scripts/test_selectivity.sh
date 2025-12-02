#!/bin/bash
# test_selectivity.sh - v2.5 선택적 채널 라우팅 테스트

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3002}"
STORE_ID="${STORE_ID:-1}"

echo "=== v2.5 선택적 채널 라우팅 테스트 ==="
echo ""

# 테스트 케이스
test_cases=(
    "IG만:ig_enabled=true,tt_enabled=false,yt_enabled=false,kakao_enabled=false,naver_enabled=false"
    "TT만:ig_enabled=false,tt_enabled=true,yt_enabled=false,kakao_enabled=false,naver_enabled=false"
    "IG+YT:ig_enabled=true,tt_enabled=false,yt_enabled=true,kakao_enabled=false,naver_enabled=false"
    "전체:ig_enabled=true,tt_enabled=true,yt_enabled=true,kakao_enabled=true,naver_enabled=true"
    "0개:ig_enabled=false,tt_enabled=false,yt_enabled=false,kakao_enabled=false,naver_enabled=false"
)

for test_case in "${test_cases[@]}"; do
    IFS=':' read -r name params <<< "$test_case"
    echo "테스트: $name"
    
    # 매장 설정 업데이트
    ig=$(echo "$params" | grep -o 'ig_enabled=[^,]*' | cut -d'=' -f2)
    tt=$(echo "$params" | grep -o 'tt_enabled=[^,]*' | cut -d'=' -f2)
    yt=$(echo "$params" | grep -o 'yt_enabled=[^,]*' | cut -d'=' -f2)
    kakao=$(echo "$params" | grep -o 'kakao_enabled=[^,]*' | cut -d'=' -f2)
    naver=$(echo "$params" | grep -o 'naver_enabled=[^,]*' | cut -d'=' -f2)
    
    curl -s -XPUT "${BASE_URL}/stores/${STORE_ID}/channel-prefs" \
        -H 'Content-Type: application/json' \
        -d "{
            \"ig_enabled\": $ig,
            \"tt_enabled\": $tt,
            \"yt_enabled\": $yt,
            \"kakao_enabled\": $kakao,
            \"naver_enabled\": $naver
        }" | jq -r '.message // .error // "OK"'
    
    # 동물 등록 및 스케줄 확인
    response=$(curl -s -XPOST "${BASE_URL}/animals" \
        -H 'Content-Type: application/json' \
        -d "{
            \"store_id\": $STORE_ID,
            \"name\": \"테스트_${name}\",
            \"type\": \"dog\"
        }")
    
    scheduled=$(echo "$response" | jq -r '.data.scheduled_channels[]? // empty' | tr '\n' ',' | sed 's/,$//')
    
    if [ -z "$scheduled" ]; then
        echo "  → 스케줄된 채널: 없음 (전송 없음)"
    else
        echo "  → 스케줄된 채널: $scheduled"
    fi
    
    echo ""
done

echo "=== 테스트 완료 ==="


