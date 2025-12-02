#!/bin/bash
set -e

echo "=== Git 히스토리 완전 재설정 ==="
cd "/Users/atlink/Desktop/파트너스 공고플랫폼/petlink_partners_ai_ads_all_results_master/extracted/production"

echo ""
echo "⚠️  이 스크립트는 Git 히스토리를 완전히 삭제하고 새로 시작합니다."
echo "   원격 저장소의 모든 내용도 덮어씁니다."
echo ""

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current)
echo "현재 브랜치: $CURRENT_BRANCH"

echo ""
echo "1. 원격 저장소 백업 (참고용)..."
git remote -v

echo ""
echo "2. Git 히스토리 완전 삭제..."
rm -rf .git

echo ""
echo "3. 새로운 Git 저장소 초기화..."
git init
git branch -M main

echo ""
echo "4. 원격 저장소 연결..."
git remote add origin https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master.git 2>/dev/null || \
git remote set-url origin https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master.git

echo ""
echo "5. .gitignore 확인..."
if [ -f .gitignore ]; then
    echo "   ✓ .gitignore 파일이 존재합니다."
    grep -E "node_modules|\.next" .gitignore && echo "   ✓ node_modules 및 .next가 .gitignore에 포함되어 있습니다." || echo "   ⚠️  .gitignore에 node_modules/.next가 없습니다."
else
    echo "   ⚠️  .gitignore 파일이 없습니다."
fi

echo ""
echo "6. 파일 추가 (.gitignore에 따라 node_modules는 자동 제외)..."
git add .

echo ""
echo "7. node_modules 확인..."
NODE_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
echo "   node_modules/.next 파일 수: $NODE_COUNT"

if [ "$NODE_COUNT" -gt 0 ]; then
    echo "   ⚠️  node_modules가 여전히 포함되어 있습니다. 수동 제거 중..."
    git ls-files | grep -E "node_modules|\.next" | xargs git rm --cached 2>/dev/null || true
    NODE_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
    echo "   제거 후 파일 수: $NODE_COUNT"
fi

echo ""
echo "8. 초기 커밋 생성..."
git commit -m "Initial commit: PetLink Partners AI Ads Platform

- 매장 등록 페이지: ID 추출 보강 + submit 버튼 testid 부여
- 온보딩 테스트: 등록 후 테스트가 /plans로 주도 이동
- 정책 차단 테스트: 동일 패턴 적용
- 전체 프로덕션 소스 코드 포함
- node_modules 및 빌드 아티팩트 제외 (.gitignore 적용)"

echo ""
echo "9. 최종 확인..."
FINAL_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "   ✓ node_modules 및 .next가 완전히 제거되었습니다."
else
    echo "   ⚠️  경고: 여전히 $FINAL_COUNT 개의 파일이 포함되어 있습니다."
    echo "   다음 파일들을 확인하세요:"
    git ls-files | grep -E "node_modules|\.next" | head -5
fi

echo ""
echo "10. GitHub에 강제 푸시 중..."
git push -u origin main --force

echo ""
echo "=== 완료 ==="
echo "GitHub 저장소: https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master"

