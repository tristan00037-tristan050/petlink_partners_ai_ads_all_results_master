#!/usr/bin/env bash
# 서버 상태 확인 스크립트

echo "🔍 서버 상태 확인 중..."
echo ""

# Owner Portal (3003) 확인
if curl -s http://localhost:3003 > /dev/null 2>&1; then
  echo "✅ Owner Portal (3003) - 실행 중"
else
  echo "❌ Owner Portal (3003) - 실행 안 됨"
  echo "   ⚠️  이 폴더는 패치 파일 모음입니다. 실제 프로젝트 루트에서 실행하세요."
  echo "   실행 방법:"
  echo "   1. 실제 프로젝트 루트로 이동"
  echo "   2. cd apps/owner && npm run dev"
  echo "   또는 SETUP_GUIDE.md 참고"
fi

# Backend (5903) 확인
if curl -s http://localhost:5903 > /dev/null 2>&1; then
  echo "✅ Backend (5903) - 실행 중"
else
  echo "❌ Backend (5903) - 실행 안 됨"
  echo "   실행 방법: 백엔드 서버를 시작하세요"
fi

echo ""
echo "테스트 실행 전 두 서버가 모두 실행 중이어야 합니다."

