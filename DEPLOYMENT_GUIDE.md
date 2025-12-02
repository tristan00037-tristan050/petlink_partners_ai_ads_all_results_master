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
