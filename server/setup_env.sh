#!/bin/bash
# r4.1 환경변수 설정 스크립트

if [ ! -f .env ]; then
  cp .env.example .env
fi

# r4.1 필수 환경변수 추가
grep -q "JWT_SECRET=change-me-please" .env || echo "JWT_SECRET=change-me-please" >> .env
grep -q "JWT_TTL_SEC=3600" .env || echo "JWT_TTL_SEC=3600" >> .env
grep -q "RATE_LIMIT_WINDOW_SEC=60" .env || echo "RATE_LIMIT_WINDOW_SEC=60" >> .env
grep -q "RATE_LIMIT_MAX=120" .env || echo "RATE_LIMIT_MAX=120" >> .env
grep -q "CORS_ORIGIN=\*" .env || echo "CORS_ORIGIN=*" >> .env
grep -q "METRICS_ENABLED=true" .env || echo "METRICS_ENABLED=true" >> .env

echo "✅ 환경변수 설정 완료"
