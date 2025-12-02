#!/usr/bin/env bash
set -euo pipefail

# v2.3 계약서 적립 기능 테스트 스크립트

MGMT=http://localhost:3002        # pet_management_ms
SUBS=http://localhost:3004        # subscription_service
FRAN=http://localhost:3005        # franchise_service

STORE_ID=1        # 테스트 대상 지점 ID
CONTRACT_ID=1001  # 테스트 계약 ID
HQ_ORG_ID=10      # 테스트 HQ ID

echo "=== v2.3 계약서 적립 기능 테스트 ==="
echo ""

# 1) CONTRACT_CREDIT → wallet.balance 증가
echo "1) CONTRACT_CREDIT → wallet.balance 증가 테스트"
echo "   (A) HQ 기본 정책 설정"
curl -s -XPUT "$FRAN/hq/bonus-policy" -H "Content-Type: application/json" -d "{
  \"hq_org_id\": $HQ_ORG_ID,
  \"per_page\": 1000, \"per_contract_max\": 8, \"monthly_pages_max\": 200,
  \"ocr_threshold\": 0.95, \"window_days\": 14
}" | jq '.'
echo ""

echo "   (B) 업로드 전 잔액 확인"
BEFORE_WALLET=$(curl -s "$SUBS/stores/$STORE_ID/wallet")
echo "$BEFORE_WALLET" | jq '.'
BEFORE_BALANCE=$(echo "$BEFORE_WALLET" | jq -r '.wallet.current_balance // 0')
echo "   잔액: $BEFORE_BALANCE원"
echo ""

echo "   (C) 3페이지 업로드 (ocr_confidence=0.99)"
# 테스트용 더미 파일 생성 (실제로는 파일이 필요하지만 테스트용)
echo "test content" > /tmp/test_contract.txt
UPLOAD_RESP=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID/files" \
  -F "file=@/tmp/test_contract.txt" \
  -F "store_id=$STORE_ID" \
  -F "metadata={\"store_id\":$STORE_ID,\"ocr_confidence\":0.99,\"page_count\":3}")
echo "$UPLOAD_RESP" | jq '.'
echo ""

echo "   (D) 계약별 적립 확인"
BONUS_RESP=$(curl -s "$MGMT/contracts/$CONTRACT_ID/bonus")
echo "$BONUS_RESP" | jq '.'
PAGES_CREDITED=$(echo "$BONUS_RESP" | jq -r '.pages_credited // 0')
AMOUNT=$(echo "$BONUS_RESP" | jq -r '.amount // 0')
STATUS=$(echo "$BONUS_RESP" | jq -r '.status // "PENDING"')
echo "   적립: ${PAGES_CREDITED}장, 금액: ${AMOUNT}원, 상태: $STATUS"
echo ""

echo "   (E) 업로드 후 잔액 확인"
AFTER_WALLET=$(curl -s "$SUBS/stores/$STORE_ID/wallet")
echo "$AFTER_WALLET" | jq '.'
AFTER_BALANCE=$(echo "$AFTER_WALLET" | jq -r '.wallet.current_balance // 0')
echo "   잔액: $AFTER_BALANCE원"
echo "   증가액: $((AFTER_BALANCE - BEFORE_BALANCE))원"
echo ""

if [ "$STATUS" = "APPROVED" ] && [ "$PAGES_CREDITED" -eq 3 ] && [ "$AMOUNT" -eq 3000 ]; then
    echo "   ✅ PASS: pages_credited=3, amount=3000, status=APPROVED"
else
    echo "   ❌ FAIL: 예상과 다른 결과"
fi
echo ""

# 2) 계약당 상한 테스트
echo "2) 계약당 상한(8장) 강제 테스트"
CONTRACT_ID_12P=1002
UPLOAD_12P=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID_12P/files" \
  -F "file=@/tmp/test_contract.txt" \
  -F "store_id=$STORE_ID" \
  -F "metadata={\"store_id\":$STORE_ID,\"ocr_confidence\":0.99,\"page_count\":12}")
echo "$UPLOAD_12P" | jq '.'
BONUS_12P=$(curl -s "$MGMT/contracts/$CONTRACT_ID_12P/bonus")
PAGES_12P=$(echo "$BONUS_12P" | jq -r '.pages_credited // 0')
if [ "$PAGES_12P" -eq 8 ]; then
    echo "   ✅ PASS: 12페이지 요청 → 8페이지 적립 (상한 적용)"
else
    echo "   ❌ FAIL: 예상 8페이지, 실제 ${PAGES_12P}페이지"
fi
echo ""

# 3) 월 상한 테스트
echo "3) 월 상한(200장) 강제 테스트"
echo "   월간 사용량 확인:"
SUMMARY=$(curl -s "$MGMT/wallet/bonus/summary?store_id=$STORE_ID")
echo "$SUMMARY" | jq '.'
MONTHLY_USED=$(echo "$SUMMARY" | jq -r '.usage.pages_used // 0')
echo "   현재 월간 사용량: ${MONTHLY_USED}장"
echo ""

# 4) OCR 임계값 테스트
echo "4) OCR 임계값(>=0.95) 자동 승인 테스트"
CONTRACT_ID_096=3001
UPLOAD_096=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID_096/files" \
  -F "file=@/tmp/test_contract.txt" \
  -F "store_id=$STORE_ID" \
  -F "metadata={\"store_id\":$STORE_ID,\"ocr_confidence\":0.96,\"page_count\":2}")
STATUS_096=$(echo "$UPLOAD_096" | jq -r '.status // "PENDING"')
if [ "$STATUS_096" = "APPROVED" ]; then
    echo "   ✅ PASS: OCR 0.96 → 자동 승인"
else
    echo "   ❌ FAIL: OCR 0.96 → $STATUS_096 (예상: APPROVED)"
fi

CONTRACT_ID_080=3002
UPLOAD_080=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID_080/files" \
  -F "file=@/tmp/test_contract.txt" \
  -F "store_id=$STORE_ID" \
  -F "metadata={\"store_id\":$STORE_ID,\"ocr_confidence\":0.80,\"page_count\":2}")
STATUS_080=$(echo "$UPLOAD_080" | jq -r '.status // "PENDING"')
if [ "$STATUS_080" = "PENDING" ]; then
    echo "   ✅ PASS: OCR 0.80 → 검수 대기"
else
    echo "   ❌ FAIL: OCR 0.80 → $STATUS_080 (예상: PENDING)"
fi
echo ""

# 5) 중복 방지 테스트
echo "5) 중복 방지 테스트"
DUP_RESP=$(curl -s -XPOST "$MGMT/contracts/$CONTRACT_ID/files" \
  -F "file=@/tmp/test_contract.txt" \
  -F "store_id=$STORE_ID" \
  -F "metadata={\"store_id\":$STORE_ID,\"ocr_confidence\":0.99,\"page_count\":3}")
if echo "$DUP_RESP" | jq -e '.duplicate == true or .existing_bonus != null' > /dev/null; then
    echo "   ✅ PASS: 중복 파일/계약 차단"
else
    echo "   ❌ FAIL: 중복 방지 실패"
    echo "$DUP_RESP" | jq '.'
fi
echo ""

# 6) HQ 정책 커스터마이징 테스트
echo "6) HQ 정책 커스터마이징 테스트"
curl -s -XPUT "$FRAN/hq/bonus-policy" -H "Content-Type: application/json" -d "{
  \"hq_org_id\": $HQ_ORG_ID,
  \"per_page\": 1000, \"per_contract_max\": 5, \"monthly_pages_max\": 50,
  \"ocr_threshold\": 0.97, \"window_days\": 14
}" | jq '.'
POLICY_CHECK=$(curl -s "$FRAN/hq/bonus-policy/$HQ_ORG_ID")
echo "$POLICY_CHECK" | jq '.'
PER_CONTRACT=$(echo "$POLICY_CHECK" | jq -r '.policy.per_contract_max // 0')
if [ "$PER_CONTRACT" -eq 5 ]; then
    echo "   ✅ PASS: HQ 정책 설정 확인 (per_contract_max=5)"
else
    echo "   ❌ FAIL: 예상 5, 실제 ${PER_CONTRACT}"
fi
echo ""

echo "=== 테스트 완료 ==="


