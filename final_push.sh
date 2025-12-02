#!/bin/bash
set -e

echo "=== 최종 Git 푸시 스크립트 ==="
cd "/Users/atlink/Desktop/파트너스 공고플랫폼/petlink_partners_ai_ads_all_results_master/extracted/production"

echo ""
echo "1. 현재 상태 확인..."
git status --short | head -5

echo ""
echo "2. 이전 커밋으로 되돌리기 (변경사항은 유지)..."
git reset --soft HEAD~1 2>&1 || echo "   이미 첫 번째 커밋입니다."

echo ""
echo "3. 모든 파일을 Git에서 제거하고 다시 추가..."
git rm -rf --cached . 2>&1 | head -3
git add . 2>&1 | head -3

echo ""
echo "4. node_modules 확인..."
NODE_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
echo "   node_modules/.next 파일 수: $NODE_COUNT"

if [ "$NODE_COUNT" -gt 0 ]; then
    echo "   ⚠️  node_modules가 여전히 포함되어 있습니다. 수동 제거 중..."
    git ls-files | grep -E "node_modules|\.next" | xargs git rm --cached 2>/dev/null || true
    NODE_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
    echo "   제거 후 파일 수: $NODE_COUNT"
fi

echo ""
echo "5. 커밋 생성..."
git commit -m "Initial commit: PetLink Partners AI Ads Platform

- 매장 등록 페이지: ID 추출 보강 + submit 버튼 testid 부여
- 온보딩 테스트: 등록 후 테스트가 /plans로 주도 이동
- 정책 차단 테스트: 동일 패턴 적용
- 전체 프로덕션 소스 코드 포함
- node_modules 및 빌드 아티팩트 제외 (.gitignore 적용)" 2>&1

echo ""
echo "6. 최종 확인..."
FINAL_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "   ✓ node_modules 및 .next가 완전히 제거되었습니다."
else
    echo "   ⚠️  경고: 여전히 $FINAL_COUNT 개의 파일이 포함되어 있습니다."
fi

echo ""
echo "7. GitHub에 강제 푸시 중..."
git push -u origin main --force 2>&1

echo ""
echo "=== 완료 ==="
echo "GitHub 저장소: https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master"

