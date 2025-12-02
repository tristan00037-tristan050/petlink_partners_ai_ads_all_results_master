#!/usr/bin/env bash

set -euo pipefail

DOMAIN="www.petlinkpartnet.co.kr"
PORT="${PORT:-5902}"

echo "=== 로컬 도메인 매핑 설정 ==="
echo
echo "도메인: ${DOMAIN}"
echo "로컬 서버 포트: ${PORT}"
echo

# 방법 1: /etc/hosts 파일 수정
if [ "$(id -u)" = "0" ]; then
  if ! grep -q "petlinkpartnet.co.kr" /etc/hosts; then
    echo "127.0.0.1 ${DOMAIN} petlinkpartnet.co.kr" >> /etc/hosts
    echo "✅ /etc/hosts 파일에 도메인 매핑 추가 완료"
  else
    echo "⚠️  /etc/hosts에 이미 petlinkpartnet.co.kr 매핑이 있습니다"
  fi
else
  echo "⚠️  sudo 권한이 필요합니다. 다음 명령어를 실행하세요:"
  echo "   sudo sh -c 'echo \"127.0.0.1 ${DOMAIN} petlinkpartnet.co.kr\" >> /etc/hosts'"
fi

echo
echo "=== 설정 완료 ==="
echo "브라우저에서 다음 주소로 접근하세요:"
echo "  http://${DOMAIN}:${PORT}"
echo "  또는"
echo "  http://petlinkpartnet.co.kr:${PORT}"
echo
echo "HTTPS를 사용하려면 nginx 프록시를 설정하세요."

