#!/bin/bash

# GitHub 푸시 문제 해결 스크립트

set -e

echo "=== GitHub 푸시 문제 해결 ==="
echo ""

# 현재 디렉토리 확인
CURRENT_DIR=$(pwd)
echo "현재 디렉토리: $CURRENT_DIR"

# 원격 저장소 상태 확인
echo "1. 원격 저장소 상태 확인 중..."
git fetch origin 2>&1 || echo "   원격 저장소 연결 확인 필요"

# 원격 브랜치 확인
if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "   원격 main 브랜치가 존재합니다."
    echo "   원격 커밋 확인:"
    git log origin/main --oneline -3 2>&1 || echo "   원격 커밋 없음"
else
    echo "   원격 main 브랜치가 없습니다."
fi

echo ""
echo "2. 해결 방법 선택:"
echo ""
echo "   옵션 A: 원격 저장소 내용 병합 (안전)"
echo "   옵션 B: 원격 저장소 덮어쓰기 (주의: 원격 내용 삭제)"
echo ""
read -p "선택 (A/B, 기본값: A): " choice
choice=${choice:-A}

if [ "$choice" = "B" ] || [ "$choice" = "b" ]; then
    echo ""
    echo "⚠️  경고: 원격 저장소의 모든 내용이 삭제됩니다!"
    read -p "계속하시겠습니까? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        echo ""
        echo "3. 원격 저장소 덮어쓰기 중..."
        git push -u origin main --force
        echo "   ✓ 완료!"
    else
        echo "   취소되었습니다."
        exit 0
    fi
else
    echo ""
    echo "3. 원격 저장소 내용 병합 중..."
    
    # 원격 브랜치가 있으면 병합
    if git show-ref --verify --quiet refs/remotes/origin/main; then
        echo "   원격 변경사항 가져오기..."
        git pull origin main --allow-unrelated-histories --no-edit || {
            echo "   병합 충돌 발생. 수동 해결이 필요할 수 있습니다."
            echo "   충돌 해결 후 다음 명령어 실행:"
            echo "   git add ."
            echo "   git commit -m 'Merge remote-tracking branch'"
            echo "   git push -u origin main"
            exit 1
        }
    fi
    
    echo ""
    echo "4. GitHub에 푸시 중..."
    git push -u origin main
    echo "   ✓ 완료!"
fi

echo ""
echo "=== 완료 ==="
echo "GitHub 저장소: https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master"

