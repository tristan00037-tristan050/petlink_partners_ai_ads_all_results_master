#!/usr/bin/env bash
# 실전 서비스 배포를 위한 소스 분리 스크립트
# 웹앱, 서버, 어드민을 각각 독립적으로 배포 가능하도록 준비

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROD_DIR="${BASE_DIR}/production"

echo "═══════════════════════════════════════════════════════════════"
echo "실전 서비스 소스 분리 시작"
echo "═══════════════════════════════════════════════════════════════"

# 디렉토리 생성
mkdir -p "${PROD_DIR}"/{webapp,server,admin}

# ============================================================================
# 1. 웹앱 (WebApp) - 클라이언트용 프론트엔드
# ============================================================================
echo ""
echo "[1/3] 웹앱 소스 준비 중..."

# 웹앱 파일 복사
cp -r "${BASE_DIR}/frontend" "${PROD_DIR}/webapp/"
cp -r "${BASE_DIR}/web" "${PROD_DIR}/webapp/"
cp "${BASE_DIR}/server/public/app.html" "${PROD_DIR}/webapp/index.html" 2>/dev/null || true
cp -r "${BASE_DIR}/server/public/app-ui" "${PROD_DIR}/webapp/" 2>/dev/null || true

# 웹앱 package.json 생성
cat > "${PROD_DIR}/webapp/package.json" <<'EOF'
{
  "name": "petlink-partners-webapp",
  "version": "1.0.0",
  "description": "PetLink Partners WebApp - Client Frontend",
  "scripts": {
    "start": "npx serve -s . -l 3000",
    "build": "echo 'Static files ready for deployment'",
    "dev": "npx serve -s . -l 3000"
  },
  "dependencies": {},
  "devDependencies": {
    "serve": "^14.2.1"
  }
}
EOF

# 웹앱 README 생성
cat > "${PROD_DIR}/webapp/README.md" <<'EOF'
# PetLink Partners - WebApp

클라이언트용 프론트엔드 웹앱입니다.

## 구조

- `frontend/` - 메인 클라이언트 화면
- `web/` - v2.5 UI 시스템
- `index.html` - 통합 SPA 진입점
- `app-ui/` - App UI 컴포넌트

## 배포

### 정적 파일 서버 (예: Nginx)

```nginx
server {
    listen 80;
    server_name app.petlink.kr;
    root /path/to/webapp;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### Node.js serve 사용

```bash
npm install
npm start
```

## 환경 변수

웹앱은 API 서버 URL을 환경 변수로 받습니다:

```bash
export API_BASE_URL=https://api.petlink.kr
```

## API 엔드포인트

웹앱은 다음 API를 호출합니다:
- `/auth/*` - 인증
- `/advertiser/*` - 광고주 정보
- `/ads/*` - 광고 관리
- `/stores/*` - 매장 관리
- `/animals/*` - 동물 관리
- `/ads/billing/*` - 결제

## CORS

API 서버에서 `APP_ORIGIN` 환경 변수에 웹앱 도메인을 설정해야 합니다.
EOF

# 웹앱 .env.example 생성
cat > "${PROD_DIR}/webapp/.env.example" <<'EOF'
# API 서버 URL
API_BASE_URL=http://localhost:5902

# 웹앱 도메인 (CORS 설정용)
APP_ORIGIN=http://localhost:3000
EOF

echo "✅ 웹앱 준비 완료"

# ============================================================================
# 2. 서버 (Server) - 백엔드 API
# ============================================================================
echo ""
echo "[2/3] 서버 소스 준비 중..."

# 서버 파일 복사
cp -r "${BASE_DIR}/server" "${PROD_DIR}/server/"
cp -r "${BASE_DIR}/scripts" "${PROD_DIR}/server/" 2>/dev/null || true
cp -r "${BASE_DIR}/migrations" "${PROD_DIR}/server/" 2>/dev/null || true
cp -r "${BASE_DIR}/db" "${PROD_DIR}/server/" 2>/dev/null || true
cp -r "${BASE_DIR}/config" "${PROD_DIR}/server/" 2>/dev/null || true
cp -r "${BASE_DIR}/policy" "${PROD_DIR}/server/" 2>/dev/null || true
cp "${BASE_DIR}/package.json" "${PROD_DIR}/server/" 2>/dev/null || true
cp "${BASE_DIR}/package-lock.json" "${PROD_DIR}/server/" 2>/dev/null || true

# 서버에서 웹앱/어드민 관련 정적 파일 제거
rm -rf "${PROD_DIR}/server/server/public/app.html" 2>/dev/null || true
rm -rf "${PROD_DIR}/server/server/public/index.html" 2>/dev/null || true
rm -rf "${PROD_DIR}/server/server/public/admin-ui" 2>/dev/null || true

# 서버 package.json 생성
cat > "${PROD_DIR}/server/package.json" <<'EOF'
{
  "name": "petlink-partners-server",
  "version": "1.0.0",
  "description": "PetLink Partners API Server",
  "main": "server/app.js",
  "scripts": {
    "start": "node server/app.js",
    "dev": "node server/app.js",
    "migrate": "node scripts/run_sql.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "express-pino-logger": "^7.0.0",
    "express-rate-limit": "^8.2.1",
    "helmet": "^8.1.0",
    "luxon": "^3.7.2",
    "pg": "^8.16.3",
    "pino": "^10.1.0",
    "undici": "^7.16.0",
    "zod": "^4.1.12",
    "cors": "^2.8.5",
    "json2csv": "^6.1.0"
  }
}
EOF

# 서버 README 생성
cat > "${PROD_DIR}/server/README.md" <<'EOF'
# PetLink Partners - API Server

백엔드 API 서버입니다.

## 구조

- `server/` - Express.js 서버 코드
- `server/routes/` - API 라우트
- `server/lib/` - 공통 라이브러리
- `server/mw/` - 미들웨어
- `server/bootstrap/` - 부트스트랩 스크립트
- `migrations/` - 데이터베이스 마이그레이션
- `scripts/` - 유틸리티 스크립트

## 환경 변수

```bash
# 서버 설정
PORT=5902
NODE_ENV=production

# 데이터베이스
DATABASE_URL=postgres://user:pass@localhost:5432/petlink

# CORS 설정
APP_ORIGIN=https://app.petlink.kr
ADMIN_ORIGIN=https://admin.petlink.kr
CORS_ORIGINS=https://app.petlink.kr,https://admin.petlink.kr

# 인증
ADMIN_KEY=your-secure-admin-key
JWT_SECRET=your-jwt-secret

# 기타
OIDC_ISSUER=https://oidc.provider.com
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
```

## 실행

```bash
npm install
npm start
```

## API 엔드포인트

### 클라이언트 API (APP_ORIGIN)
- `POST /auth/login` - 로그인
- `POST /auth/signup` - 회원가입
- `GET /advertiser/profile` - 프로필 조회
- `POST /ads/*` - 광고 관리
- `GET /stores/*` - 매장 관리
- `POST /animals/*` - 동물 등록

### 관리자 API (ADMIN_ORIGIN)
- `GET /admin/*` - 관리자 기능
- 헤더: `X-Admin-Key: your-admin-key`

## 데이터베이스 마이그레이션

```bash
npm run migrate scripts/migrations/001_init.sql
```

## 보안

- CORS: APP_ORIGIN과 ADMIN_ORIGIN 분리
- 인증: JWT 토큰 (클라이언트), X-Admin-Key (관리자)
- Rate Limiting: 기본 120 req/min
- Security Headers: Helmet 적용
EOF

# 서버 .env.example 생성
cat > "${PROD_DIR}/server/.env.example" <<'EOF'
# 서버 설정
PORT=5902
NODE_ENV=production

# 데이터베이스
DATABASE_URL=postgres://postgres:petpass@localhost:5432/petlink

# CORS 설정
APP_ORIGIN=http://localhost:3000
ADMIN_ORIGIN=http://localhost:8000
CORS_ORIGINS=http://localhost:3000,http://localhost:8000

# 인증
ADMIN_KEY=admin-dev-key-123
JWT_SECRET=your-jwt-secret-key-change-in-production

# OIDC (선택)
OIDC_ISSUER=
OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=

# 기타
LOG_LEVEL=info
EOF

echo "✅ 서버 준비 완료"

# ============================================================================
# 3. 어드민 (Admin) - 관리자 대시보드
# ============================================================================
echo ""
echo "[3/3] 어드민 소스 준비 중..."

# 어드민 파일 복사
mkdir -p "${PROD_DIR}/admin"
cp "${BASE_DIR}/server/public/index.html" "${PROD_DIR}/admin/index.html" 2>/dev/null || true
cp -r "${BASE_DIR}/server/public/admin-ui" "${PROD_DIR}/admin/" 2>/dev/null || true

# 어드민 package.json 생성
cat > "${PROD_DIR}/admin/package.json" <<'EOF'
{
  "name": "petlink-partners-admin",
  "version": "1.0.0",
  "description": "PetLink Partners Admin Dashboard",
  "scripts": {
    "start": "npx serve -s . -l 8000",
    "build": "echo 'Static files ready for deployment'",
    "dev": "npx serve -s . -l 8000"
  },
  "dependencies": {},
  "devDependencies": {
    "serve": "^14.2.1"
  }
}
EOF

# 어드민 README 생성
cat > "${PROD_DIR}/admin/README.md" <<'EOF'
# PetLink Partners - Admin Dashboard

관리자 대시보드입니다.

## 구조

- `index.html` - 관리자 대시보드 메인
- `admin-ui/` - 관리자 UI 컴포넌트

## 배포

### 정적 파일 서버 (예: Nginx)

```nginx
server {
    listen 80;
    server_name admin.petlink.kr;
    root /path/to/admin;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### Node.js serve 사용

```bash
npm install
npm start
```

## 환경 변수

어드민은 API 서버 URL을 환경 변수로 받습니다:

```bash
export API_BASE_URL=https://api.petlink.kr
export ADMIN_KEY=your-admin-key
```

## API 엔드포인트

어드민은 다음 API를 호출합니다:
- `/admin/*` - 모든 관리자 기능
- 헤더에 `X-Admin-Key` 필요

## CORS

API 서버에서 `ADMIN_ORIGIN` 환경 변수에 어드민 도메인을 설정해야 합니다.
EOF

# 어드민 .env.example 생성
cat > "${PROD_DIR}/admin/.env.example" <<'EOF'
# API 서버 URL
API_BASE_URL=http://localhost:5902

# 어드민 도메인 (CORS 설정용)
ADMIN_ORIGIN=http://localhost:8000

# 어드민 키
ADMIN_KEY=admin-dev-key-123
EOF

echo "✅ 어드민 준비 완료"

# ============================================================================
# 배포 가이드 생성
# ============================================================================
cat > "${PROD_DIR}/DEPLOYMENT_GUIDE.md" <<'EOF'
# 실전 서비스 배포 가이드

## 구조

프로덕션 소스는 세 가지로 분리되어 있습니다:

1. **webapp/** - 클라이언트용 웹앱 (정적 파일)
2. **server/** - 백엔드 API 서버 (Node.js)
3. **admin/** - 관리자 대시보드 (정적 파일)

## 배포 순서

### 1. 데이터베이스 설정

```bash
# PostgreSQL 설치 및 데이터베이스 생성
createdb petlink
psql petlink < server/migrations/001_init.sql
```

### 2. API 서버 배포

```bash
cd server
npm install
cp .env.example .env
# .env 파일 수정
npm start
```

**환경 변수 설정:**
- `DATABASE_URL` - PostgreSQL 연결 문자열
- `APP_ORIGIN` - 웹앱 도메인 (CORS)
- `ADMIN_ORIGIN` - 어드민 도메인 (CORS)
- `ADMIN_KEY` - 관리자 인증 키
- `JWT_SECRET` - JWT 서명 키

### 3. 웹앱 배포

```bash
cd webapp
npm install
# 정적 파일을 Nginx 또는 CDN에 배포
```

**Nginx 설정 예시:**
```nginx
server {
    listen 80;
    server_name app.petlink.kr;
    root /path/to/webapp;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### 4. 어드민 배포

```bash
cd admin
npm install
# 정적 파일을 Nginx 또는 CDN에 배포
```

**Nginx 설정 예시:**
```nginx
server {
    listen 80;
    server_name admin.petlink.kr;
    root /path/to/admin;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

## 도메인 설정

### 권장 도메인 구조

- **웹앱**: `https://app.petlink.kr`
- **어드민**: `https://admin.petlink.kr`
- **API**: `https://api.petlink.kr`

### CORS 설정

API 서버의 `.env` 파일에서:

```bash
APP_ORIGIN=https://app.petlink.kr
ADMIN_ORIGIN=https://admin.petlink.kr
CORS_ORIGINS=https://app.petlink.kr,https://admin.petlink.kr
```

## 보안 체크리스트

- [ ] `ADMIN_KEY` 강력한 키로 변경
- [ ] `JWT_SECRET` 강력한 키로 변경
- [ ] 데이터베이스 비밀번호 강력하게 설정
- [ ] HTTPS 적용
- [ ] CORS 정확히 설정
- [ ] Rate Limiting 활성화
- [ ] Security Headers 적용 확인
- [ ] 환경 변수 파일 `.env` 보안 (`.gitignore` 확인)

## 모니터링

- API 서버 로그 확인
- 데이터베이스 연결 상태 확인
- CORS 오류 모니터링
- Rate Limiting 트리거 확인

## 문제 해결

### CORS 오류
- API 서버의 `APP_ORIGIN`, `ADMIN_ORIGIN` 확인
- 브라우저 콘솔에서 정확한 오류 메시지 확인

### API 연결 실패
- API 서버 실행 상태 확인
- 방화벽 설정 확인
- 네트워크 연결 확인

### 인증 실패
- `ADMIN_KEY` 일치 확인
- JWT 토큰 유효성 확인
EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ 실전 서비스 소스 분리 완료"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "생성된 디렉토리:"
echo "  - production/webapp/  (클라이언트 웹앱)"
echo "  - production/server/   (백엔드 API 서버)"
echo "  - production/admin/    (관리자 대시보드)"
echo ""
echo "다음 단계:"
echo "  1. 각 디렉토리의 README.md 확인"
echo "  2. .env.example을 .env로 복사하고 설정"
echo "  3. DEPLOYMENT_GUIDE.md 참고하여 배포"
echo ""

