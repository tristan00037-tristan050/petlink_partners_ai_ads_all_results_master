#!/usr/bin/env bash
set -euo pipefail

# 기존 프로세스 종료
if lsof -ti:5903 > /dev/null 2>&1; then
  echo "🛑 기존 서버 종료 중..."
  lsof -ti:5903 | xargs kill -9 2>/dev/null || true
  sleep 1
fi

# .env 로드
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

echo "🚀 P0 API 서버 시작 중..."
node src/index.js > logs/p0-api.log 2>&1 &
SERVER_PID=$!

sleep 2

if ps -p $SERVER_PID > /dev/null; then
  echo "✅ 서버 시작 완료 (PID: $SERVER_PID)"
  echo "   로그: logs/p0-api.log"
  echo "   URL: http://localhost:5903"
else
  echo "❌ 서버 시작 실패"
  tail -20 logs/p0-api.log
  exit 1
fi
