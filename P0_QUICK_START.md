# P0 개발 빠른 시작 가이드

## 개발 환경 설정

### 1. 웹앱 (webapp/)

```bash
cd webapp
npm install
npm run dev  # 또는 npx serve -s . -l 3000
```

**Mock 서버 사용 (서버 미연결 상태)**:
- MSW (Mock Service Worker) 설정
- 또는 오프라인 JSON 주입 UI

### 2. 서버 (server/)

```bash
cd server
npm install
cp .env.example .env
# .env 파일 수정 (DATABASE_URL, APP_ORIGIN, ADMIN_ORIGIN 등)
npm start
```

**OpenAPI Mock 서버**:
```bash
# OpenAPI 기반 mock 서버로 시작
npx @openapitools/openapi-generator-cli generate -i openapi/auth.yaml -g nodejs-express-server
```

### 3. 어드민 (admin/)

```bash
cd admin
npm install
npm run dev  # 또는 npx serve -s . -l 8000
```

## 개발 순서

### Sprint 0 (3일)
1. OpenAPI 정의 (auth.yaml, stores.yaml, plans.yaml, campaigns.yaml, admin.yaml)
2. DDL 마이그레이션 (store_plan_subscriptions, policy_violations)
3. FE 라우팅/상태 뼈대
4. PolicyEngine 인터페이스

### Sprint 1 (7일)
1. My Store 페이지
2. 캠페인 생성 (AI 카피 포함)
3. PolicyEngine 룰+텍스트 AI
4. Admin 목록/상세

### Sprint 2 (7일)
1. BillingScheduler
2. Admin 승인/반려
3. 이미지 1차 필터
4. E2E 테스트

## 핵심 규칙

### 로그인 플로우
- 회원가입/첫 로그인 → 홈(Home) 이동
- My Store 미완성 시: 배너/CTA 노출 + 버튼은 My Store로 이동

### 서버 검증
```javascript
// POST /campaigns
if (!store.isComplete) {
  return res.status(400).json({
    code: "STORE_PROFILE_INCOMPLETE",
    message: "매장 정보를 먼저 완성해 주세요."
  });
}
```

### PolicyEngine 결과
```json
{
  "approved": false,
  "decision": "REJECT",
  "reasons": [...],
  "suggested_body": "...",
  "suggested_hashtags": [...]
}
```

### BillingScheduler
- D-2/D-1/D: 예정 알림
- D+1 미납: status=OVERDUE, campaigns → PAUSED_BY_BILLING
- 결제 완료: 자동 재개

## 동결 항목

❌ **개발 금지**:
- 램핑/TV Dash 고도화
- 75%/100% 승격 스크립트
- 램핑 알고리즘 튜닝

✅ **보호 대상**:
- 계약서 적립 기능 (현행 유지)

## 참고 문서

- `P0_DEVELOPMENT_GUIDE.md` - 상세 개발 지침
- `P0_TASK_BREAKDOWN.md` - 작업 분해
- `DEPLOYMENT_GUIDE.md` - 배포 가이드
