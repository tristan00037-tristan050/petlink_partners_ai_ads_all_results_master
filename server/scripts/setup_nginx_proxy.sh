#!/usr/bin/env bash

set -euo pipefail

DOMAIN="www.petlinkpartnet.co.kr"
BACKEND_PORT="${PORT:-5902}"

echo "=== Nginx 프록시 설정 ==="
echo
echo "도메인: ${DOMAIN}"
echo "백엔드 포트: ${BACKEND_PORT}"
echo

# nginx 설치 확인
if ! command -v nginx >/dev/null 2>&1; then
  echo "⚠️  nginx가 설치되어 있지 않습니다."
  echo "   macOS: brew install nginx"
  echo "   또는 간단한 Node.js 프록시를 사용하세요 (setup_simple_proxy.sh)"
  exit 1
fi

# nginx 설정 파일 생성
NGINX_CONF="/usr/local/etc/nginx/servers/petlinkpartnet.conf"
if [ -d "/etc/nginx/sites-available" ]; then
  NGINX_CONF="/etc/nginx/sites-available/petlinkpartnet"
fi

cat > "${NGINX_CONF}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN} petlinkpartnet.co.kr;

    location / {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

echo "✅ Nginx 설정 파일 생성: ${NGINX_CONF}"
echo
echo "다음 명령어를 실행하세요:"
if [ -d "/etc/nginx/sites-available" ]; then
  echo "  sudo ln -s ${NGINX_CONF} /etc/nginx/sites-enabled/"
fi
echo "  sudo nginx -t  # 설정 테스트"
echo "  sudo nginx -s reload  # nginx 재시작"
echo
echo "그 후 브라우저에서 http://${DOMAIN} 로 접근하세요."

