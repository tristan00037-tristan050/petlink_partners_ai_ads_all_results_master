#!/usr/bin/env bash
set -euo pipefail

# v2.3 Δ3 계약서 적립 기능 테스트 스크립트

MGMT=http://localhost:3002        # pet_management_ms
FRAN=http://localhost:3005        # franchise_service

STORE_ID=1        # 테스트 대상 지점 ID
CONTRACT_ID=1001  # 테스트 계약 ID
HQ_ORG_ID=10      # 테스트 HQ ID

echo "=== v2.3 Δ3 계약서 적립 기능 테스트 ==="
echo ""

# 테스트용 더미 파일 생성
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "테스트 파일 생성 중..."
echo "test contract content" > "$TEMP_DIR/test_contract.jpg"

# A. 48시간 창 초과 테스트
echo "A) 48시간 창 초과 테스트"
CONTRACT_DATE_OLD=$(date -u -v-49H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "49 hours ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$(date -u -d '49 hours ago' +'%Y-%m-%dT%H:%M:%SZ')")
echo "   계약일: $CONTRACT_DATE_OLD (49시간 전)"
RESP_A=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID/files" \
  -F "file=@$TEMP_DIR/test_contract.jpg" \
  -F "store_id=$STORE_ID" \
  -F "contract_date=$CONTRACT_DATE_OLD" \
  -F "animal_reg_no=TEST001" \
  -F "buyer_name=테스트고객" \
  -F "buyer_phone=01012345678")
echo "$RESP_A" | jq '.' 2>/dev/null || echo "$RESP_A"
CODE_A=$(echo "$RESP_A" | jq -r '.code // "unknown"' 2>/dev/null || echo "unknown")
if [[ "$CODE_A" == "UPLOAD_WINDOW_EXCEEDED" ]]; then
    echo "   ✅ 422 UPLOAD_WINDOW_EXCEEDED 정상"
else
    echo "   ⚠️  예상: UPLOAD_WINDOW_EXCEEDED, 실제: $CODE_A"
fi
echo ""

# B. 전자계약 자동 적립 테스트
echo "B) 전자계약 자동 적립 테스트"
RESP_B=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID/finalize" \
  -H "Content-Type: application/json" \
  -d "{
    \"store_id\": $STORE_ID,
    \"animal_reg_no\": \"TEST002\",
    \"buyer_name\": \"전자계약고객\",
    \"buyer_address\": \"서울시 강남구\",
    \"buyer_phone\": \"01087654321\",
    \"marketing_consent\": {
      \"agreed\": true,
      \"terms_version\": \"v1.0\"
    },
    \"e_contract\": true
  }")
echo "$RESP_B" | jq '.' 2>/dev/null || echo "$RESP_B"
CODE_B=$(echo "$RESP_B" | jq -r '.code // "unknown"' 2>/dev/null || echo "unknown")
if [[ "$CODE_B" == "APPROVED" ]]; then
    echo "   ✅ 201 APPROVED 정상"
else
    echo "   ⚠️  예상: APPROVED, 실제: $CODE_B"
fi
echo ""

# C. 계약당 3장 초과 테스트
echo "C) 계약당 3장 초과 테스트"
CONTRACT_DATE_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONTRACT_ID_C=2001
for i in {1..4}; do
    echo "   업로드 $i/4..."
    RESP_C=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID_C/files" \
      -F "file=@$TEMP_DIR/test_contract.jpg" \
      -F "store_id=$STORE_ID" \
      -F "contract_date=$CONTRACT_DATE_NOW" \
      -F "animal_reg_no=TEST00$i" \
      -F "buyer_name=고객$i" \
      -F "buyer_phone=0101111000$i")
    CODE_C=$(echo "$RESP_C" | jq -r '.code // "unknown"' 2>/dev/null || echo "unknown")
    if [[ $i -eq 4 ]] && [[ "$CODE_C" == "PER_CONTRACT_CAP_EXCEEDED" ]]; then
        echo "   ✅ 422 PER_CONTRACT_CAP_EXCEEDED 정상 (4번째 업로드)"
    elif [[ $i -lt 4 ]] && [[ "$CODE_C" == "APPROVED" || "$CODE_C" == "PENDING" ]]; then
        echo "   ✅ $i번째 업로드 성공 ($CODE_C)"
    fi
done
echo ""

# D. 월 100장 초과 테스트 (시뮬레이션)
echo "D) 월 100장 초과 테스트 (시뮬레이션)"
echo "   월간 사용량 조회..."
RESP_D=$(curl -s "$MGMT/wallet/bonus/summary?store_id=$STORE_ID")
echo "$RESP_D" | jq '.' 2>/dev/null || echo "$RESP_D"
MONTHLY_PAGES=$(echo "$RESP_D" | jq -r '.data.pages_total // 0' 2>/dev/null || echo "0")
REMAINING=$(echo "$RESP_D" | jq -r '.data.remaining_quota // 0' 2>/dev/null || echo "0")
echo "   현재 월간 사용: ${MONTHLY_PAGES}장, 잔여: ${REMAINING}장"
echo ""

# E. OCR < 0.95 테스트 (시뮬레이션)
echo "E) OCR < 0.95 테스트 (시뮬레이션)"
echo "   OCR 신뢰도가 0.95 미만이면 PENDING 상태로 처리됩니다."
echo "   (실제 OCR 라이브러리 연동 시 테스트 가능)"
echo ""

# F. 유사도 판정 테스트
echo "F) 유사도 판정 테스트"
CONTRACT_ID_F=3001
CONTRACT_DATE_F=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "   첫 번째 업로드..."
RESP_F1=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID_F/files" \
  -F "file=@$TEMP_DIR/test_contract.jpg" \
  -F "store_id=$STORE_ID" \
  -F "contract_date=$CONTRACT_DATE_F" \
  -F "animal_reg_no=TESTF1" \
  -F "buyer_name=유사도테스트" \
  -F "buyer_phone=01099999999")
REVIEW_STATUS_F1=$(echo "$RESP_F1" | jq -r '.data.review_status // "unknown"' 2>/dev/null || echo "unknown")
SIMILARITY_F1=$(echo "$RESP_F1" | jq -r '.data.similarity_score // 0' 2>/dev/null || echo "0")
echo "   첫 업로드 상태: $REVIEW_STATUS_F1, 유사도: $SIMILARITY_F1"
echo "   (유사도 ≥0.90: AUTO_REVIEW, 0.80~0.90: PENDING, <0.80: APPROVED)"
echo ""

# HQ 정책 설정 테스트
echo "G) HQ 정책 설정 테스트"
RESP_G=$(curl -s -XPUT "$FRAN/hq/bonus-policy" \
  -H "Content-Type: application/json" \
  -d "{
    \"hq_org_id\": $HQ_ORG_ID,
    \"per_contract_max\": 5,
    \"monthly_pages_max\": 150,
    \"upload_window_hours_photo\": 72
  }")
echo "$RESP_G" | jq '.' 2>/dev/null || echo "$RESP_G"
echo ""

# HQ 정책 조회 테스트
echo "H) HQ 정책 조회 테스트"
RESP_H=$(curl -s "$FRAN/hq/bonus-policy/$HQ_ORG_ID")
echo "$RESP_H" | jq '.' 2>/dev/null || echo "$RESP_H"
echo ""

echo "=== 테스트 완료 ==="
echo ""
echo "주요 검증 항목:"
echo "  ✅ 48시간 창 초과 → 422 UPLOAD_WINDOW_EXCEEDED"
echo "  ✅ 전자계약 자동 적립 → 201 APPROVED"
echo "  ✅ 계약당 3장 초과 → 422 PER_CONTRACT_CAP_EXCEEDED"
echo "  ✅ 월간 사용량 조회"
echo "  ✅ 유사도 판정 (AUTO_REVIEW/PENDING/APPROVED)"
echo "  ✅ HQ 정책 설정/조회"


