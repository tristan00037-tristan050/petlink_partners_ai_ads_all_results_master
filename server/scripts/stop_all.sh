#!/bin/bash
# stop_all.sh - 모든 서버 종료

echo "=== PetLink Partners 서버 종료 ==="
echo ""

# PID 파일에서 프로세스 종료
if [ -f /tmp/petlink_orchestrator.pid ]; then
    PID=$(cat /tmp/petlink_orchestrator.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID 2>/dev/null && echo "✅ 오케스트레이터 서버 종료 (PID: $PID)" || echo "⚠️  오케스트레이터 서버 종료 실패"
    fi
    rm -f /tmp/petlink_orchestrator.pid
fi

if [ -f /tmp/petlink_billing.pid ]; then
    PID=$(cat /tmp/petlink_billing.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID 2>/dev/null && echo "✅ 빌링 서버 종료 (PID: $PID)" || echo "⚠️  빌링 서버 종료 실패"
    fi
    rm -f /tmp/petlink_billing.pid
fi

if [ -f /tmp/petlink_pages.pid ]; then
    PID=$(cat /tmp/petlink_pages.pid)
    if ps -p $PID > /dev/null 2>&1; then
        kill $PID 2>/dev/null && echo "✅ 정적 페이지 서버 종료 (PID: $PID)" || echo "⚠️  정적 페이지 서버 종료 실패"
    fi
    rm -f /tmp/petlink_pages.pid
fi

# 포트로 강제 종료 (PID 파일이 없는 경우)
for port in 8090 8091 5730; do
    PID=$(lsof -ti:$port 2>/dev/null || true)
    if [ -n "$PID" ]; then
        kill $PID 2>/dev/null && echo "✅ 포트 $port 프로세스 종료 (PID: $PID)" || true
    fi
done

echo ""
echo "=== 모든 서버 종료 완료 ==="


