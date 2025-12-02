#!/bin/bash

# Git 저장소 초기화 및 GitHub 연결 스크립트

set -e

echo "=== PetLink Partners AI Ads Platform - Git 설정 ==="
echo ""

# 현재 디렉토리 확인
CURRENT_DIR=$(pwd)
echo "현재 디렉토리: $CURRENT_DIR"

# Git 저장소 초기화
if [ ! -d ".git" ]; then
    echo "1. Git 저장소 초기화 중..."
    git init
    echo "   ✓ Git 저장소 초기화 완료"
else
    echo "1. Git 저장소가 이미 존재합니다."
fi

# 원격 저장소 설정
GITHUB_URL="https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master.git"
echo ""
echo "2. 원격 저장소 설정 중..."
if git remote get-url origin >/dev/null 2>&1; then
    echo "   기존 원격 저장소 제거 중..."
    git remote remove origin
fi
git remote add origin "$GITHUB_URL"
echo "   ✓ 원격 저장소 연결 완료: $GITHUB_URL"

# 원격 저장소 확인
echo ""
echo "3. 원격 저장소 확인:"
git remote -v

# 파일 추가
echo ""
echo "4. 파일 추가 중..."
git add .

# 커밋 생성
echo ""
echo "5. 초기 커밋 생성 중..."
git commit -m "Initial commit: PetLink Partners AI Ads Platform

- 매장 등록 페이지: ID 추출 보강 + submit 버튼 testid 부여
- 온보딩 테스트: 등록 후 테스트가 /plans로 주도 이동
- 정책 차단 테스트: 동일 패턴 적용
- 전체 프로덕션 소스 코드 포함"

echo ""
echo "6. GitHub 저장소에 푸시 중..."
echo "   브랜치: main"
git branch -M main
git push -u origin main

echo ""
echo "=== 완료 ==="
echo "GitHub 저장소에 성공적으로 푸시되었습니다!"
echo "URL: $GITHUB_URL"

