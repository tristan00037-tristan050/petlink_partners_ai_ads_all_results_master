#!/bin/bash
set -e

echo "=== Git 히스토리 완전 재작성 (큰 파일 제거) ==="
cd "/Users/atlink/Desktop/파트너스 공고플랫폼/petlink_partners_ai_ads_all_results_master/extracted/production"

echo ""
echo "⚠️  이 스크립트는 Git 히스토리를 완전히 재작성합니다."
echo "   현재 커밋의 모든 파일을 새로 커밋합니다."
echo ""

# 현재 브랜치 확인
CURRENT_BRANCH=$(git branch --show-current)
echo "현재 브랜치: $CURRENT_BRANCH"

echo ""
echo "1. 모든 파일을 스테이징 영역에서 제거..."
git rm -rf --cached . 2>/dev/null || true

echo ""
echo "2. .gitignore에 따라 파일 다시 추가 (node_modules 제외)..."
git add .

echo ""
echo "3. node_modules가 포함되어 있는지 확인..."
NODE_MODULES_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
if [ "$NODE_MODULES_COUNT" -gt 0 ]; then
    echo "   ⚠️  경고: $NODE_MODULES_COUNT 개의 node_modules/.next 파일이 여전히 포함되어 있습니다."
    echo "   수동으로 제거합니다..."
    git ls-files | grep -E "node_modules|\.next" | xargs git rm --cached 2>/dev/null || true
fi

echo ""
echo "4. 최종 확인..."
FINAL_COUNT=$(git ls-files | grep -E "node_modules|\.next" | wc -l | tr -d ' ')
if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "   ✓ node_modules 및 .next가 완전히 제거되었습니다."
else
    echo "   ⚠️  여전히 $FINAL_COUNT 개의 파일이 남아있습니다."
    echo "   다음 파일들을 확인하세요:"
    git ls-files | grep -E "node_modules|\.next" | head -5
fi

echo ""
echo "5. 새로운 커밋 생성..."
git commit -m "Initial commit: PetLink Partners AI Ads Platform

- 매장 등록 페이지: ID 추출 보강 + submit 버튼 testid 부여
- 온보딩 테스트: 등록 후 테스트가 /plans로 주도 이동
- 정책 차단 테스트: 동일 패턴 적용
- 전체 프로덕션 소스 코드 포함
- node_modules 및 빌드 아티팩트 제외 (.gitignore 적용)"

echo ""
echo "6. GitHub에 강제 푸시 중..."
git push -u origin main --force

echo ""
echo "=== 완료 ==="
echo "GitHub 저장소: https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master"

