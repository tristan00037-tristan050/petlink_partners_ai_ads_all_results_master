#!/bin/bash
# run_orchestrator.sh - 오케스트레이션 서버 실행(:8090)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVER_DIR="${PROJECT_ROOT}/server"

cd "${SERVER_DIR}"

# Node.js 확인
if ! command -v node >/dev/null 2>&1; then
    echo "오류: Node.js가 설치되어 있지 않습니다."
    exit 1
fi

# 의존성 설치 (필요 시)
if [ ! -d "node_modules" ]; then
    echo "의존성 설치 중..."
    npm init -y >/dev/null 2>&1 || true
    npm install express cors >/dev/null 2>&1 || true
fi

# 서버 실행
echo "오케스트레이션 서버 시작 중... (포트: 8090)"
echo ""
echo "엔드포인트:"
echo "  PUT/GET http://localhost:8090/api/stores/:id/channel-prefs"
echo "  PUT/GET http://localhost:8090/api/stores/:id/radius"
echo "  PUT/GET http://localhost:8090/api/stores/:id/weights"
echo "  GET  http://localhost:8090/api/pacer/preview"
echo "  GET  http://localhost:8090/healthz"
echo ""
echo "종료하려면 Ctrl+C를 누르세요."
echo ""

node orchestrator.js


