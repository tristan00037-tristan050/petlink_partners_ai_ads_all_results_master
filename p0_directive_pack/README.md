# P0 Directive Pack

P0 개발을 위한 통합 패키지입니다.

## 구성

- `/docs/README_P0_Directive_Final.md` - P0 개발 지침(최종본)
- `/openapi/openapi_p0.yaml` - API 스켈레톤 (통합)
- `/migrations/20251117_p0_core.sql` - PostgreSQL DDL 초안
- `/policy/policy_ruleset.example.json` - 정책 룰 샘플
- `/server_stubs/express/app.js` - Express 서버 스텁

## 빠른 시작

### 1. 서버 스텁 실행

```bash
cd server_stubs/express
npm install
node app.js  # http://localhost:5903
```

### 2. DDL 적용

```bash
psql -d petlink -f migrations/20251117_p0_core.sql
```

### 3. OpenAPI 확인

`openapi/openapi_p0.yaml` 파일을 열어 API 스펙을 확인하세요.

## 다음 단계

1. D0 킥오프: 문서 배포, 스키마 확정
2. Sprint 1: My Store, 캠페인 생성, PolicyEngine 구현
3. Sprint 2: BillingScheduler, Admin UI, E2E 테스트

## 참고

- `docs/README_P0_Directive_Final.md` - 상세 개발 지침
- 품질 루브릭 준수 필수
- 동결 항목 개발 금지
- 계약서 적립 기능 보호
