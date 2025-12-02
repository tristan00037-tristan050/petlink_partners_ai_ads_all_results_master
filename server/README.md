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
