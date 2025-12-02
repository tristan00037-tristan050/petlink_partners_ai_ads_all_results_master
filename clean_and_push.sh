#!/bin/bash
set -e

echo "=== Git 히스토리 정리 및 푸시 ==="
cd "/Users/atlink/Desktop/파트너스 공고플랫폼/petlink_partners_ai_ads_all_results_master/extracted/production"

echo ""
echo "1. 현재 커밋 확인..."
git log --oneline -1

echo ""
echo "2. Git에서 node_modules 및 .next 제거 중..."
git rm -r --cached apps/owner/node_modules 2>/dev/null || true
git rm -r --cached server/node_modules 2>/dev/null || true
find . -name "node_modules" -type d -exec git rm -r --cached {} \; 2>/dev/null || true
find . -name ".next" -type d -exec git rm -r --cached {} \; 2>/dev/null || true

echo ""
echo "3. 변경사항 확인..."
git status --short | head -10

echo ""
echo "4. 커밋 수정 중..."
git commit --amend --no-edit || git commit -m "Initial commit: PetLink Partners AI Ads Platform

- 매장 등록 페이지: ID 추출 보강 + submit 버튼 testid 부여
- 온보딩 테스트: 등록 후 테스트가 /plans로 주도 이동
- 정책 차단 테스트: 동일 패턴 적용
- 전체 프로덕션 소스 코드 포함
- node_modules 및 빌드 아티팩트 제외 (.gitignore 적용)"

echo ""
echo "5. node_modules가 Git에 포함되어 있는지 확인..."
NODE_MODULES_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
if [ "$NODE_MODULES_COUNT" -gt 0 ]; then
    echo "   ⚠️  경고: 아직 $NODE_MODULES_COUNT 개의 node_modules/.next 파일이 Git에 포함되어 있습니다."
    echo "   다음 명령어로 수동 제거:"
    echo "   git ls-files | grep -E 'node_modules|\.next' | xargs git rm --cached"
else
    echo "   ✓ node_modules 및 .next가 Git에서 제거되었습니다."
fi

echo ""
echo "6. GitHub에 강제 푸시 중..."
git push -u origin main --force

echo ""
echo "=== 완료 ==="
echo "GitHub 저장소: https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master"

