# Sprint 2 진행 요약

## 완료된 작업

### 서버 (Server)
- ✅ BillingScheduler 통합 (`server/app_p0.js`)
  - 크론 작업 시작 (매일 새벽 2시 알림, 3시 미납 처리)
- ✅ Admin 승인/반려 API (`server/routes/admin_campaigns.js`)
  - GET /admin/campaigns (목록 조회)
  - GET /admin/campaigns/:id (상세 조회)
  - PATCH /admin/campaigns/:id/approve (승인)
  - PATCH /admin/campaigns/:id/reject (반려)
- ✅ Admin 매장 관리 API (`server/routes/admin_stores.js`)
  - GET /admin/stores (목록 조회)
  - PATCH /admin/stores/:id/status (상태 변경)
- ✅ 이미지 1차 필터 (`server/lib/image_filter.js`)
  - 파일 크기, 형식, 해상도 검증
- ✅ Auth API (`server/routes/auth.js`)
  - POST /auth/signup, POST /auth/login, GET /auth/me
- ✅ Plans API (`server/routes/plans.js`)
  - GET /plans, GET /stores/me/plan, POST /stores/me/plan
- ✅ 미들웨어
  - `mw/auth.js` - JWT 발급/검증
  - `mw/admin_gate.js` - Admin 인증
  - `mw/cors_split.js` - App/Admin CORS 분리
  - `mw/corr.js` - Correlation ID
  - `mw/audit_logger.js` - 감사 로깅
- ✅ DB 유틸리티 (`server/lib/db.js`)
  - PostgreSQL 연결 풀, 성능 로깅

### 성능 최적화
- ✅ DB 쿼리 성능 로깅 (200ms 이상 경고)
- ✅ API 응답 성능 로깅 (200ms 이상 경고)
- ✅ 인덱스 최적화 (DDL에 포함)

## 다음 작업

- E2E 테스트 시나리오 작성 및 실행
- 이미지 필터 통합 (캠페인 생성 시)
- 성능 벤치마크 및 최적화

## 실행 방법

### 서버 실행
```bash
cd server
node app_p0.js  # http://localhost:5903
```

### 환경 변수
```bash
export DATABASE_URL="postgres://postgres:petpass@localhost:5432/petlink"
export ADMIN_KEY="admin-dev-key-123"
export APP_ORIGIN="http://localhost:5902"
export ADMIN_ORIGIN="http://localhost:8000"
export JWT_SECRET="p0-jwt-secret-key-change-in-production"
```

## API 엔드포인트

### App API
- POST /auth/signup
- POST /auth/login
- GET /auth/me
- GET /stores/me
- PUT /stores/me
- GET /plans
- GET /stores/me/plan
- POST /stores/me/plan
- POST /campaigns
- GET /campaigns
- GET /campaigns/:id
- PATCH /campaigns/:id/:action

### Admin API
- GET /admin/stores
- PATCH /admin/stores/:id/status
- GET /admin/campaigns
- GET /admin/campaigns/:id
- PATCH /admin/campaigns/:id/approve
- PATCH /admin/campaigns/:id/reject
