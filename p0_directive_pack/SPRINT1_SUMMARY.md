# Sprint 1 진행 요약

## 완료된 작업

### 웹앱 (WebApp)
- ✅ SPA 라우터 (`webapp/src/router.js`)
- ✅ API 클라이언트 (`webapp/src/services/api.js`)
- ✅ 홈 대시보드 (`webapp/src/pages/home.js`) - A1
- ✅ My Store 페이지 (`webapp/src/pages/store.js`) - A2
- ✅ 플랜 선택 페이지 (`webapp/src/pages/plans.js`) - A3
- ✅ 캠페인 생성 플로우 (`webapp/src/pages/campaign-create.js`) - A4
- ✅ 광고 관리 (`webapp/src/pages/campaigns.js`) - A5
- ✅ 로그인/회원가입 (`webapp/src/pages/auth.js`)

### 서버 (Server)
- ✅ Campaigns API Routes (`server/routes/campaigns.js`)
  - POST /campaigns (STORE_PROFILE_INCOMPLETE 검증)
  - GET /campaigns
  - GET /campaigns/:id
  - PATCH /campaigns/:id/:action
- ✅ Stores API Routes (`server/routes/stores.js`)
  - GET /stores/me
  - PUT /stores/me (is_complete 계산)
- ✅ PolicyEngine (`server/lib/policy_engine.js`)
- ✅ BillingScheduler (`server/bootstrap/billing_scheduler.js`)

### 어드민 (Admin)
- ✅ 매장 목록 (`admin/src/pages/stores.js`) - D1
- ✅ 광고 목록/상세 (`admin/src/pages/campaigns.js`) - D2
- ✅ Admin API 클라이언트 (`admin/src/services/api.js`)

## 다음 작업 (Sprint 2)

- BillingScheduler 통합 및 테스트
- Admin 승인/반려 API 구현
- 이미지 1차 필터
- E2E 테스트
- 성능 최적화 (200ms 응답)

## 실행 방법

### 서버 스텁
```bash
cd p0_directive_pack/server_stubs/express
npm install && node app.js
```

### DDL 적용
```bash
psql -d petlink -f p0_directive_pack/migrations/20251117_p0_core.sql
```

### 웹앱 개발
```bash
cd webapp
npm install
npm run dev
```
