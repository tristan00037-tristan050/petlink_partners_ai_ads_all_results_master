#!/bin/bash
# serve_pages.sh - 정적 페이지 서버 실행(:5720)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEB_DIR="${PROJECT_ROOT}/web"

cd "${WEB_DIR}"

# Python 확인
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo "오류: Python이 설치되어 있지 않습니다."
    exit 1
fi

# 서버 실행
echo "정적 페이지 서버 시작 중... (포트: 5730)"
echo ""
echo "페이지:"
echo "  http://localhost:5730/pages/pricing.html"
echo "  http://localhost:5730/pages/invoice.html"
echo "  http://localhost:5730/pages/plan_switch.html"
echo "  http://localhost:5730/pages/channel_prefs.html"
echo ""
echo "종료하려면 Ctrl+C를 누르세요."
echo ""

${PYTHON_CMD} -m http.server 5730

