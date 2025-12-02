#!/usr/bin/env bash
set -euo pipefail

# v2.4 통합 테스트 스크립트
# 모든 주요 API 엔드포인트 테스트

BASE_URL="http://localhost:3002"
STORE_ID=1
CONTRACT_ID=1001
HQ_ORG_ID=10

LOG_DIR="staging_proof/logs"
mkdir -p "$LOG_DIR"

echo "=== v2.4 통합 테스트 시작 ==="
echo ""

# A. 계약서 업로드 (48h 창, 3장, 100장 제한)
echo "A) 계약서 업로드 테스트"
CONTRACT_DATE_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "test contract" > /tmp/test_contract.jpg

RESP_A=$(curl -s -XPOST "$BASE_URL/contracts/$CONTRACT_ID/files" \
  -F "file=@/tmp/test_contract.jpg" \
  -F "store_id=$STORE_ID" \
  -F "contract_date=$CONTRACT_DATE_NOW" \
  -F "animal_reg_no=TEST001" \
  -F "buyer_name=테스트고객" \
  -F "buyer_phone=01012345678" \
  -F "description=사랑스러운 강아지 분양 중입니다! #강아지분양 #반려동물")

echo "$RESP_A" | jq '.' > "$LOG_DIR/A_contract_upload.json" 2>/dev/null || echo "$RESP_A" > "$LOG_DIR/A_contract_upload.json"
echo "$RESP_A" | jq '.' 2>/dev/null || echo "$RESP_A"
echo ""

# B. 전자계약 완료
echo "B) 전자계약 완료 테스트"
RESP_B=$(curl -s -XPOST "$BASE_URL/contracts/$CONTRACT_ID/finalize" \
  -H "Content-Type: application/json" \
  -d "{
    \"store_id\": $STORE_ID,
    \"animal_reg_no\": \"TEST002\",
    \"buyer_name\": \"전자계약고객\",
    \"buyer_phone\": \"01087654321\",
    \"marketing_consent\": {
      \"agreed\": true,
      \"terms_version\": \"v1.0\"
    },
    \"e_contract\": true
  }")

echo "$RESP_B" | jq '.' > "$LOG_DIR/B_econtract_finalize.json" 2>/dev/null || echo "$RESP_B" > "$LOG_DIR/B_econtract_finalize.json"
echo "$RESP_B" | jq '.' 2>/dev/null || echo "$RESP_B"
echo ""

# C. 부정행위 검토 (원자 트랜잭션)
echo "C) 부정행위 검토 테스트"
RESP_C=$(curl -s -XPOST "$BASE_URL/fraud/review" \
  -H "Content-Type: application/json" \
  -d "{
    \"contract_id\": $CONTRACT_ID,
    \"store_id\": $STORE_ID,
    \"action\": \"SUSPEND\",
    \"penalty_level\": \"L2\",
    \"penalty_days\": 7,
    \"reason\": \"부정 적립 판정\"
  }")

echo "$RESP_C" | jq '.' > "$LOG_DIR/C_fraud_review.json" 2>/dev/null || echo "$RESP_C" > "$LOG_DIR/C_fraud_review.json"
echo "$RESP_C" | jq '.' 2>/dev/null || echo "$RESP_C"
echo ""

# D. UX 채널 수집 (유튜브)
echo "D) UX 채널 수집 테스트 (유튜브)"
RESP_D=$(curl -s -XPOST "$BASE_URL/ingest/youtube" \
  -H "Content-Type: application/json" \
  -d "{
    \"store_id\": $STORE_ID,
    \"channel_id\": \"UCtest123\",
    \"channel_name\": \"테스트 채널\",
    \"contents\": [
      {
        \"external_id\": \"video001\",
        \"title\": \"강아지 분양 영상\",
        \"description\": \"사랑스러운 강아지 분양 중입니다\",
        \"url\": \"https://youtube.com/watch?v=test001\",
        \"thumbnail_url\": \"https://img.youtube.com/test001.jpg\",
        \"view_count\": 1000,
        \"like_count\": 50,
        \"comment_count\": 10,
        \"published_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
      }
    ]
  }")

echo "$RESP_D" | jq '.' > "$LOG_DIR/D_ingest_youtube.json" 2>/dev/null || echo "$RESP_D" > "$LOG_DIR/D_ingest_youtube.json"
echo "$RESP_D" | jq '.' 2>/dev/null || echo "$RESP_D"
echo ""

# E. UX 채널 수집 (카카오)
echo "E) UX 채널 수집 테스트 (카카오)"
RESP_E=$(curl -s -XPOST "$BASE_URL/ingest/kakao" \
  -H "Content-Type: application/json" \
  -d "{
    \"store_id\": $STORE_ID,
    \"channel_id\": \"kakao_test123\",
    \"channel_name\": \"카카오 채널\",
    \"contents\": [
      {
        \"external_id\": \"post001\",
        \"title\": \"반려동물 소개\",
        \"description\": \"건강한 반려동물을 만나보세요\",
        \"url\": \"https://pf.kakao.com/test123\",
        \"view_count\": 500,
        \"like_count\": 30,
        \"comment_count\": 5,
        \"published_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
      }
    ]
  }")

echo "$RESP_E" | jq '.' > "$LOG_DIR/E_ingest_kakao.json" 2>/dev/null || echo "$RESP_E" > "$LOG_DIR/E_ingest_kakao.json"
echo "$RESP_E" | jq '.' 2>/dev/null || echo "$RESP_E"
echo ""

# F. UX 채널 수집 (네이버)
echo "F) UX 채널 수집 테스트 (네이버)"
RESP_F=$(curl -s -XPOST "$BASE_URL/ingest/naver" \
  -H "Content-Type: application/json" \
  -d "{
    \"store_id\": $STORE_ID,
    \"channel_id\": \"naver_blog_test\",
    \"channel_name\": \"네이버 블로그\",
    \"contents\": [
      {
        \"external_id\": \"blog001\",
        \"title\": \"반려동물 분양 안내\",
        \"description\": \"새로운 가족을 찾고 있습니다\",
        \"url\": \"https://blog.naver.com/test123\",
        \"view_count\": 800,
        \"like_count\": 40,
        \"comment_count\": 8,
        \"published_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
      }
    ]
  }")

echo "$RESP_F" | jq '.' > "$LOG_DIR/F_ingest_naver.json" 2>/dev/null || echo "$RESP_F" > "$LOG_DIR/F_ingest_naver.json"
echo "$RESP_F" | jq '.' 2>/dev/null || echo "$RESP_F"
echo ""

# G. 금지어 검사 테스트
echo "G) 금지어 검사 테스트"
RESP_G=$(curl -s -XPOST "$BASE_URL/contracts/$CONTRACT_ID/files" \
  -F "file=@/tmp/test_contract.jpg" \
  -F "store_id=$STORE_ID" \
  -F "contract_date=$CONTRACT_DATE_NOW" \
  -F "animal_reg_no=TEST003" \
  -F "buyer_name=테스트고객" \
  -F "buyer_phone=01011111111" \
  -F "description=강아지 분양합니다. 전화번호: 010-1234-5678")

echo "$RESP_G" | jq '.' > "$LOG_DIR/G_banned_keywords.json" 2>/dev/null || echo "$RESP_G" > "$LOG_DIR/G_banned_keywords.json"
echo "$RESP_G" | jq '.' 2>/dev/null || echo "$RESP_G"
echo ""

# H. 월간 보너스 요약
echo "H) 월간 보너스 요약 조회"
RESP_H=$(curl -s "$BASE_URL/wallet/bonus/summary?store_id=$STORE_ID")
echo "$RESP_H" | jq '.' > "$LOG_DIR/H_bonus_summary.json" 2>/dev/null || echo "$RESP_H" > "$LOG_DIR/H_bonus_summary.json"
echo "$RESP_H" | jq '.' 2>/dev/null || echo "$RESP_H"
echo ""

echo "=== 테스트 완료 ==="
echo "로그 파일 위치: $LOG_DIR/"
ls -lh "$LOG_DIR/"


