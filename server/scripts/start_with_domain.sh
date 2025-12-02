#!/usr/bin/env bash

set -euo pipefail

DOMAIN="www.petlinkpartnet.co.kr"
PORT="${PORT:-5902}"

echo "=== 로컬 도메인으로 서버 시작 ==="
echo

# 1. /etc/hosts 확인 및 안내
if ! grep -q "petlinkpartnet.co.kr" /etc/hosts 2>/dev/null; then
  echo "⚠️  /etc/hosts에 도메인 매핑이 없습니다."
  echo "   다음 명령어를 실행하세요 (sudo 권한 필요):"
  echo "   sudo sh -c 'echo \"127.0.0.1 ${DOMAIN} petlinkpartnet.co.kr\" >> /etc/hosts'"
  echo
  read -p "지금 실행하시겠습니까? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo sh -c "echo \"127.0.0.1 ${DOMAIN} petlinkpartnet.co.kr\" >> /etc/hosts" || {
      echo "❌ hosts 파일 수정 실패"
      exit 1
    }
    echo "✅ /etc/hosts 파일 수정 완료"
  fi
else
  echo "✅ /etc/hosts에 도메인 매핑이 있습니다"
fi

# 2. 서버 시작
cd "$(dirname "$0")/.."
bash start_server.sh

# 3. 접근 안내
echo
echo "=== 접근 방법 ==="
echo "브라우저에서 다음 주소로 접근하세요:"
echo "  http://${DOMAIN}:${PORT}"
echo "  또는"
echo "  http://petlinkpartnet.co.kr:${PORT}"
echo
echo "포트 없이 접근하려면 nginx 프록시를 설정하세요:"
echo "  bash scripts/setup_nginx_proxy.sh"

