#!/bin/bash
# P0 API 스텁 서버 시작 스크립트

cd "$(dirname "$0")/server_stub/node"

if [ ! -f "index.js" ]; then
  echo "❌ index.js 파일을 찾을 수 없습니다."
  exit 1
fi

if [ ! -d "node_modules" ]; then
  echo "📦 Express 설치 중..."
  npm init -y > /dev/null 2>&1
  npm i express > /dev/null 2>&1
fi

echo "🚀 P0 API 스텁 서버 시작 중..."
echo "   URL: http://localhost:3800"
echo "   Health Check: http://localhost:3800/health"
echo ""
echo "종료하려면 Ctrl+C를 누르세요"
echo ""

node index.js
