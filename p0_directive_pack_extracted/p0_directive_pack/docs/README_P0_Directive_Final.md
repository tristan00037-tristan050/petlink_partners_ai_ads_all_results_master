# P0 개발 지침 - 최종본 (v1.0)

**날짜**: 2025-11-17  
**버전**: Final

## 0) 품질 루브릭(최소 합격선, 전 과업 공통)

### 기능 적합도
- P0 스코프(회원 웹/앱 · 정책/결제 엔진 · 최소 어드민) 밖의 기능은 코드·UI 추가 금지(Freeze).

### API 계약
- `openapi_p0.yaml` 기준으로 2xx/4xx 스키마 고정 및 샘플 응답 일치.

### 검증/정책
- 필수값 미충족·정책 위반 시 구조화 코드/메시지(예: `STORE_PROFILE_INCOMPLETE`, `POLICY_REJECT`) 반환·로그 적재.

### 운영 가드 재사용
- Preflight/ACK-SLA/Origins(CORS) 통과·증빙 스냅샷 보관.

### 회귀 보호
- "계약서 적립" 기존 작성/저장/조회 완전 동일 동작(스키마/로직 불변).

### 문서·증빙
- 작업마다 README·Evidence(JSON/CSV/headers) 생성·보관.

**루브릭 미충족 시 반드시 수정 후 머지—부분 탑재 금지.**

---

## 1) 즉시 착수 산출물

### P0 Directive Pack 구성

- `/docs/README_P0_Directive_Final.md` - P0 개발 지침(최종본)
- `/openapi/openapi_p0.yaml` - API 스켈레톤
- `/migrations/20251117_p0_core.sql` - PostgreSQL DDL 초안
- `/policy/policy_ruleset.example.json` - 정책 룰 샘플
- `/server_stubs/express/app.js` - Express 서버 스텁

---

## 2) D0 킥오프(지금 실행)

### 문서 배포
`/docs/README_P0_Directive_Final.md`를 위키/슬랙 고정 공지.

### 스키마/스펙 확정(30분)

**DBA**: `/migrations/20251117_p0_core.sql` → 현행 DB와 Diff 검토(충돌 無 보장).

**BE**: `/openapi/openapi_p0.yaml` → Path/Schema 고정. (추가/변경 시 PO 승인 필수)

### 서버 스텁 가동(15분)

```bash
cd server_stubs/express
npm init -y && npm i express
node app.js   # http://localhost:5903
```

### 브랜치 전략/체크

- `main` 보호, 작업은 `feature/<EPIC>-<story>`
- 커밋: `feat(api): campaigns POST validation (STORE_PROFILE_INCOMPLETE)`
- PR 체크: OpenAPI 일치/ESLint/Test/DB 마이그레이션 dry-run

---

## 3) P0 잔여 구현 — 에픽/스토리(수용 기준 포함)

### EPIC A. 회원 웹/앱(반응형)

#### A1 홈 대시보드 & 매장등록 유도
**AC**: 최초 로그인 시 홈 진입, 미등록이면 상단 고정 배너/모달 노출, [지금 등록] CTA 동작.

#### A2 My Store(필수 필드)
**AC**: 매장명·주소·연락처·헤드라인·대표이미지 ≥1 저장/수정, 서버 검증 미통과 시 필드별 에러.

#### A3 플랜 선택/변경(P0 화면만)
**AC**: 요금제 리스트/선택 상태 저장(실 PG 연동 無), 구독 상태 표시.

#### A4 광고 생성 플로우
**AC**: 반려동물 선택/이미지(1~5)·영상 업로드/AI 카피 생성/채널 선택/미리보기/저장.

#### A5 광고 관리(리스트/상세/상태변경)
**AC**: 상태(초안/심사중/집행중/일시중지/종료) 변경·가드(미등록 매장은 생성/집행 불가).

### EPIC B. 서버 API/검증/정책엔진

#### B1 OpenAPI 구현
**AC**: Auth/Store/Plan/Campaign/Admin 엔드포인트 200/4xx 스키마 일치.

#### B2 검증(Validation)
**AC**: `POST /campaigns` 시 미완성 매장 → 400 + `STORE_PROFILE_INCOMPLETE` 코드.

#### B3 PolicyEngine(텍스트/이미지)
**AC**: 금칙어 룰 + AI 텍스트 심사 + 브랜드 세이프티 체크, `policy_violations` 기록, 제안 문구 반환.

#### B4 정책 로그 조회
**AC**: 어드민 상세에서 위반 리스트/코드/필드/키워드/스코어 확인.

### EPIC C. BillingScheduler(월 결제 상태 기반 제어)

#### C1 스케줄러
**AC**: D-2/D-1/D 배너 알림, D+1 미납 → 구독 `OVERDUE` + 캠페인 `PAUSED_BY_BILLING` 자동화.

#### C2 결제완료 처리(수동 API) & 자동 재개
**AC**: 구독 `ACTIVE` 전환 시 `PAUSED_BY_BILLING` 캠페인 자동 복귀.

### EPIC D. 어드민 최소 UI

#### D1 매장 목록/상태 관리
**AC**: 검색/필터 + 승인/정지/보류 변경·감사 로그.

#### D2 광고 목록 → 상세(승인/반려)
**AC**: 정책 로그·코멘트 기반 승인/반려, 상태 변경 API 연동.

### EPIC E. 회귀 보호(계약서 적립)

#### E1 회귀 테스트
**AC**: 계약서 작성/저장/조회 전/후 스냅샷 일치, DDL/코드 변경 없음.

---

## 4) API·DDL 핵심(패키지 기준)

### OpenAPI: `/openapi/openapi_p0.yaml` 참고

- `POST /auth/signup`, `POST /auth/login`, `GET /auth/me`
- `GET/PUT /stores/me`
- `GET /plans`, `GET/POST /stores/me/plan`
- `POST /campaigns`, `GET /campaigns`, `GET /campaigns/{id}`, `PATCH /campaigns/{id}/pause|resume|stop`
- `GET /admin/stores`, `PATCH /admin/stores/{id}/status`, `GET /admin/campaigns`, `PATCH /admin/campaigns/{id}/approve|reject`

### DDL: `/migrations/20251117_p0_core.sql`

- `stores`, `plans`, `store_plan_subscriptions`, `pets`, `campaigns`, `creatives`, `policy_violations` 등 기본키/인덱스 포함.

---

## 5) 동결(Freeze)·금지 리스트(즉시 적용)

- **램핑/TV Dash 고도화**(75%/100% 승격 스크립트, 전용 대시보드, 고급 알람): 중단(버그 대응만).
- **정책 시뮬레이터·정교 RBAC·통합 운영 대시보드·외부 알림 연동**: P2~P3로 이관.
- **"계약서 적립" 스키마/로직 변경**: 금지(PO 사전 승인 없이는 불가).

---

## 6) 머지 기준(DoD) 체크리스트

- [ ] OpenAPI와 응답 스키마 100% 일치(스냅샷 테스트 통과)
- [ ] 필수값/정책 위반 시 구조화 에러 & `policy_violations` 기록
- [ ] Preflight/ACK-SLA/Origins(CORS) 헤더 OK 증빙 파일 첨부
- [ ] "계약서 적립" 회귀 OK(샘플 작성/저장/조회 동일)
- [ ] README/증빙(Evidence) 디렉터리 추가

---

## 7) 역할 배치(권고)

- **FE(웹/앱)**: A1~A5 (2명)
- **BE(API/정책/스케줄러)**: B1~B4, C1~C2 (2명)
- **DBA**: DDL 확정·성능검토 (0.5명)
- **QA**: E2E 시나리오/회귀(계약서) (0.5명)

---

## 8) 지금 바로 실행할 커맨드

```bash
# 1) 패키지 압축 해제 후 서버 스텁 기동
cd server_stubs/express
npm init -y && npm i express
node app.js  # http://localhost:5903

# 2) OpenAPI 문서 열람 후 BE 컨트롤러/서비스 설계
#    (openapi/openapi_p0.yaml)

# 3) DDL 드라이런(개발 DB)
# psql -f migrations/20251117_p0_core.sql  (또는 마이그레이션 툴)
```

---

## 9) 질문에 대한 최종 답

지금부터 개발팀(우리)은 본 지시안과 제공된 패키지로 P0 제품 레이어를 마무리합니다.

웹앱·서버의 "운영/정산/증빙" 축은 완료 수준이며, P0 제품 기능(정책엔진·BillingScheduler·최소 어드민·회원 웹 핵심 여정·검증/로깅)을 즉시 구현에 착수합니다.

우선은 위 패키지를 내려 받아 D0 킥오프부터 진행해 주십시오.

