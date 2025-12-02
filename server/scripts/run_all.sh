#!/bin/bash
# run_all.sh - 모든 서버를 한 번에 실행

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== PetLink Partners v2.6 실행 번들 r3 ==="
echo ""

# 포트 확인
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "⚠️  포트 $port가 이미 사용 중입니다."
        return 1
    fi
    return 0
}

# 포트 확인
echo "포트 확인 중..."
check_port 8090 || exit 1
check_port 8091 || exit 1
check_port 5730 || exit 1
echo "✅ 모든 포트 사용 가능"
echo ""

# 1. 오케스트레이터 서버 (포트: 8090)
echo "1. 오케스트레이터 서버 시작 (포트: 8090)..."
cd "$SCRIPT_DIR/.."
node server/orchestrator.js &
ORCHESTRATOR_PID=$!
sleep 2
if ps -p $ORCHESTRATOR_PID > /dev/null; then
    echo "   ✅ 오케스트레이터 서버 실행 중 (PID: $ORCHESTRATOR_PID)"
else
    echo "   ❌ 오케스트레이터 서버 시작 실패"
    exit 1
fi
echo ""

# 2. 빌링 서버 (포트: 8091)
echo "2. 빌링 서버 시작 (포트: 8091)..."
node server/billing.js &
BILLING_PID=$!
sleep 2
if ps -p $BILLING_PID > /dev/null; then
    echo "   ✅ 빌링 서버 실행 중 (PID: $BILLING_PID)"
else
    echo "   ❌ 빌링 서버 시작 실패"
    kill $ORCHESTRATOR_PID 2>/dev/null || true
    exit 1
fi
echo ""

# 3. 정적 페이지 서버 (포트: 5730)
echo "3. 정적 페이지 서버 시작 (포트: 5730)..."
if command -v python3 &> /dev/null; then
    cd "$SCRIPT_DIR/.."
    python3 -m http.server 5730 > /dev/null 2>&1 &
    PAGES_PID=$!
    sleep 1
    if ps -p $PAGES_PID > /dev/null; then
        echo "   ✅ 정적 페이지 서버 실행 중 (PID: $PAGES_PID)"
    else
        echo "   ❌ 정적 페이지 서버 시작 실패"
        kill $ORCHESTRATOR_PID $BILLING_PID 2>/dev/null || true
        exit 1
    fi
else
    echo "   ⚠️  Python3가 없어 정적 페이지 서버를 건너뜁니다."
    PAGES_PID=""
fi
echo ""

# PID 저장
echo "$ORCHESTRATOR_PID" > /tmp/petlink_orchestrator.pid
echo "$BILLING_PID" > /tmp/petlink_billing.pid
[ -n "$PAGES_PID" ] && echo "$PAGES_PID" > /tmp/petlink_pages.pid

echo "=== 모든 서버 실행 완료 ==="
echo ""
echo "📋 서버 정보:"
echo "   - 오케스트레이터: http://localhost:8090"
echo "   - 빌링: http://localhost:8091"
echo "   - 정적 페이지: http://localhost:5730"
echo ""
echo "🛑 종료하려면:"
echo "   ./scripts/stop_all.sh"
echo "   또는"
echo "   kill $ORCHESTRATOR_PID $BILLING_PID${PAGES_PID:+ $PAGES_PID}"
echo ""


