# P0 개발 지침 – 집행용 최종본 (v1.0)

**날짜**: 2025-11-17

**범위**: 분양매장 회원 웹/앱, 본사 정책·결제 엔진(+최소 관리 UI), 서버(API/DB/배치)

## 원칙

아래 3축에 즉시 기여하지 않는 개발은 P2~P3로 이동하고 지금은 손대지 않음.

---

## 0) 스코프 선언(필수 3요소)

### 분양매장 회원용 웹/앱(반응형, 웹 기반)

가입/로그인 → My Store 등록/수정 → 요금제 선택 → 반려동물/이미지/영상 업로드 → AI 카피 생성(필수) → 노출 매체 선택 → 광고 생성/관리/상태 변경.

### 본사 어드민(정책·결제 엔진 + 최소 관리 UI)

- 룰 기반 금칙어/필수값 검증 + AI 콘텐츠 심사(텍스트 중심, 이미지 1차 필터)
- 브랜드 세이프티/네거티브 키워드 검사 + 안전 문구 자동 제안
- 월 결제 상태 기반 제어(예정 알림, 미납 자동 정지)
- 최소 관리 UI: 매장/광고 리스트·검색·필터, 승인/반려

### 서버(API/DB/연동)

- 엔티티: users, stores, plans, store_plan_subscriptions, pets, campaigns, creatives, policy_violations
- OpenAPI 우선 확정 → 구현 → 배치(BillingScheduler)

---

## 1) 개발 동결(Freeze) 지시 – 지금 즉시 멈출 것

### 대상: 램핑/TV Dash/관찰 고도화 전 영역

**유지·재사용(현 상태로 P0 완료로 간주)**:
- `golive.sh`, `promote_*`, `backout_*`
- `monitor_50pct_60min.sh`, `check_24h_metrics.sh`
- TV Dash JSON, ACK-SLA, Preflight, Preview2/Payout2, evidence 구조

**중단**:
- 75%/100% 신규 승격 스크립트
- 램핑 알고리즘/지표 튜닝
- TV/램핑 전용 대시보드
- 고급 알림/자동 롤백 추가

**운영 지침**: 신규 기능/튜닝/화면 추가 금지. 버그·장애 대응만 최소 유지. 코드·문서 보존.

**보류(추후 P2~P3)**: 정책 시뮬레이터, 정교 RBAC/다단계 심사, 통합 운영 대시보드, 외부 알림 연동(슬랙/SMS), 별도 심사 큐/워크플로우.

---

## 2) P0 – 바로 개발 착수 항목(Do Now)

### 2-A. 회원 웹/앱(프런트) – 핵심 여정 UX

#### 화면/흐름

**홈(Home) 대시보드**:
- 내 매장 등록 여부, 현재 플랜 요약, 최근 광고, 상단 고정 배너(등록 유도)

**My Store**: 
- 매장명(필수), 주소, 연락처, 영업시간, 한 줄 소개(필수), 본문, 대표 이미지 1~4장

**요금제 선택(S/M/L)**: 
- UI/상태만(PG 연동은 P1)

**광고 생성**: 
- 반려동물 선택/등록 → 사진 1~5 + (옵션) 영상 → AI 카피 생성(필수) → 미리보기/편집 → 채널 선택(체크박스)

**광고 관리**: 
- 리스트(썸네일/제목/채널/상태)·상세(내용, 상태 변경: 시작/일시중지/종료, 소재 교체)

**차단 규칙(프런트)**:
- 매장 정보 미완성 시 광고/요금제/캠페인 생성 버튼 클릭 → My Store로 이동(API 호출 금지)

**디자인**: 반응형 그리드, 접근성(포커스/대비), 시스템 폰트, 라이트/다크 지원(선택)

#### 수용 기준(샘플)

- 매장 필수 필드 미입력 시 모든 생성 버튼이 My Store로 안내되고, 배너/CTA가 노출됨
- AI 카피: 제목 ≤ 30자, 본문 2~3문단, 해시태그 5~10개 자동 채움 + 편집 가능

### 2-B. 정책·결제 엔진 + 최소 어드민 UI

#### B-1) PolicyEngine 삽입(서버 미들웨어)

**룰 기반 필터**: 금칙어/필수값 검증(욕설/불법/성인/학대 등 사전 정의 패턴)

**AI 심사(텍스트 중심, 이미지 기본형)**:

결과 스키마:
```json
{
  "approved": false,
  "decision": "REJECT|REVIEW|ALLOW",
  "reasons": [
    {"type":"KEYWORD","field":"body","keyword":"...","message":"금칙어"},
    {"type":"AI_POLICY","field":"body","code":"SEXUAL_CONTENT","score":0.92}
  ],
  "suggested_body":"...정제 문구...",
  "suggested_hashtags":["#책임분양", "..."]
}
```

- `policy_violations` 테이블에 항상 기록(캠페인 상태 전이 근거)
- 브랜드 세이프티: `brand_policies`(allowed_keywords[], blocked_keywords[]) 대조 → 적발 시 자동 제안(suggested_*)
- 상태 전이 예시: `DRAFT → SUBMITTED → (ALLOW→APPROVED) | (REVIEW→PENDING_REVIEW) | (REJECT→REJECTED_BY_POLICY)`

**수용 기준**:
- 금칙어 1건만 적발돼도 `policy_violations` 생성 + `REJECTED_BY_POLICY` 전이
- AI 점수 임계 초과 시 `PENDING_REVIEW` 전이 + 제안 문구 제공

#### B-2) 월 결제 스케줄러(BillingScheduler)

**데이터**: `store_plan_subscriptions`(store_id, plan_id, status, cycle_start/end, next_billing_date, last_paid_at, grace_period_days)

**크론(일 1회)**:
- D-2/D-1/D: 예정 알림(마이페이지 배너/내부 알림)
- D+1 미납: `status=OVERDUE`, 해당 매장 `RUNNING` 캠페인 → `PAUSED_BY_BILLING`, 안내 노출
- 결제 완료(수동 API): `status=ACTIVE`, `last_paid_at` 갱신 → `PAUSED_BY_BILLING` → `RUNNING` 자동 복귀

**수용 기준**:
- D+1 미납 시 해당 매장 모든 캠페인이 1회 배치 내에서 일괄 PAUSE 처리
- 결제 완료 후 1분 내 자동 재개(배치 or 즉시 훅)

#### B-3) 최소 어드민 UI(3화면)

- **매장 목록**: 검색(매장명/이메일/전화), 상태 필터, 플랜/상태 표시, 승인/정지 버튼
- **광고 목록**: 제목/매장/썸네일/상태/채널, 검색·필터, 상세 링크
- **광고 승인/반려 상세**: 콘텐츠 미리보기 + `policy_violations` 리스트, 승인/반려(코멘트) 액션

**수용 기준**:
- 모든 승인/반려는 감사 로그와 함께 상태전이가 기록됨
- 필터/검색은 3만 건 규모에서 200ms 내 응답(서버 캐시/인덱스 설계 전제)

### 2-C. 서버/API/DB – 구현 체크리스트

#### API 그룹(최소 세트, OpenAPI 우선 확정)

**Auth**: 
- `POST /auth/signup`, `POST /auth/login`, `GET /auth/me`

**Store**: 
- `GET /stores/me`, `PUT /stores/me`

**Plan**: 
- `GET /plans`, `GET /stores/me/plan`, `POST /stores/me/plan`

**Campaign**: 
- `POST /campaigns`, `GET /campaigns`, `GET /campaigns/{id}`, `PATCH /campaigns/{id}/pause|resume|stop|change-pet`

**Admin**: 
- `GET /admin/stores`, `PATCH /admin/stores/{id}/status`, `GET /admin/campaigns`, `GET /admin/campaigns/{id}`, `PATCH /admin/campaigns/{id}/approve`, `PATCH /admin/campaigns/{id}/reject`

#### DB(추가/확인)

- `store_plan_subscriptions`(상태/주기/결제일/미납/유예일)
- `policy_violations`(campaign_id, type, field, code/keyword, score, message, suggested_*, created_at)
- `campaigns` 상태 열거에 `REJECTED_BY_POLICY`, `PENDING_REVIEW`, `PAUSED_BY_BILLING` 등 반영

#### 서버 검증(Validation) – 강제 규칙

`POST /campaigns`: 해당 `store_id`의 필수 필드 미완성이면
```json
HTTP 400
{"code":"STORE_PROFILE_INCOMPLETE","message":"매장 정보를 먼저 완성해 주세요."}
```
(최초 로그인 여부와 무관하게 항상 적용)

---

## 3) 특별 지시 2건(강제)

### 로그인 플로우 변경

- 회원가입/첫 로그인 → 홈(Home) 이동(차단하지 않음)
- My Store 미완성 시: 홈 상단 고정 배너/CTA 노출 + 광고/요금제/캠페인 버튼은 My Store로 이동
- 서버 400(스토어 미완성) 규칙 상시 적용

### "계약서 적립" 기능 – 현행 유지(보호 대상)

- 스키마/로직/동작 변경 금지(버그 픽스만 예외)
- P0/P1 신규 기능이 계약서 테이블/코드에 영향 주지 않도록
- 필요 연동은 대표 승인 후 별도 태스크로 분리

---

## 4) 산출물 & 수용 기준(DoD)

- **OpenAPI**: `auth.yaml`, `stores.yaml`, `plans.yaml`, `campaigns.yaml`, `admin.yaml` (스키마/예제 포함)
- **DDL 마이그레이션**: `store_plan_subscriptions`, `policy_violations` 등 추가/변경 스크립트
- **PolicyEngine 모듈**: 룰/AI 결과 스키마 & 상태전이 단위테스트
- **BillingScheduler**: D-2/D-1/D 알림 + D+1 자동 정지 + 결제 완료 자동 재개 테스트
- **최소 어드민 UI 3화면**: 목록/상세/승인·반려 플로우, 200ms 응답 가이드 충족
- **회원 웹/앱**: 핵심 여정(가입→매장→AI카피→채널→생성/관리) 데모 가능
- **QA 스크립트**: cURL/HTTPie/REST Client 파일, 주요 해피/에러 케이스
- **운영 가이드**: 배치 스케줄/롤백/알림 문구, 정책 로그 해석법

---

## 5) 일정(권고, 2주 스프린트 × 2)

- **Sprint 0(3일)**: OpenAPI/DDL 동결, FE 라우팅/상태 뼈대, PolicyEngine 인터페이스
- **Sprint 1(7일)**: My Store/캠페인 생성·AI 카피, PolicyEngine 룰+텍스트 AI, Admin 목록/상세
- **Sprint 2(7일)**: BillingScheduler, Admin 승인/반려, 이미지 1차 필터, 전체 E2E/품질 게이트
- **RC/릴리즈(2일)**: 하드닝/보안 헤더/CORS 최종, 문서화/데모

**RACI(예시)**:
- FE: 회원 웹/앱 + 어드민 3화면 – Responsible
- BE: API/DB/Policy/Billing – Responsible
- QA/PO: 수용 기준/시나리오 – Accountable/Consulted

---

## 6) 리스크 & 완화

- **정책 과잉차단**: 룰/AI 임계 분리, REVIEW 단계 운용
- **미납 오탐**: 배치 쿼리 & 상태전이 멱등성, 리트라이/감사로그
- **이미지 심사 한계**: 1차(형식/용량/노출감지) 후 고도화는 P1~P2

---

## 7) 로컬 실행(개발 편의) – 서버 미연결 상태

**프런트 미리보기**:
- `npm run dev`(Vite) → http://localhost:5173 (Mock Service Worker/MSW 사용 권장)
- 또는 `dist/` 빌드 후 `index.html` 파일 직접 오픈(오프라인 JSON 주입 UI 제공 권장)

**서버**: OpenAPI 기반 mock 서버로 시작 → 실제 구현 연결

※ 별도 요청 시, **오프라인 데모 HTML(디자인/UX 적용, JSON 업로더 내장)**도 제공 가능합니다.
(서버 없이 파일만 더블클릭으로 확인)

---

## 8) 백로그 분류(지금 개발하지 않음)

- **P1**: PG 연동, 이메일/SMS 알림, 이미지/영상 고급 모더레이션, 어드민 승인 큐 편의 기능
- **P2~P3**: 정책 시뮬레이터, 고급 RBAC/다단계 심사, 통합 대시보드, 외부 알림/티켓 연동

---

## 부록 A — API 수용 기준(예시 스니펫)

### POST /campaigns (스토어 미완성)

```
400 Bad Request
Content-Type: application/json
{"code":"STORE_PROFILE_INCOMPLETE","message":"매장 정보를 먼저 완성해 주세요."}
```

### PolicyEngine 결과 예

```json
{
  "approved": false,
  "decision": "REJECT",
  "reasons": [
    {"type":"KEYWORD","field":"body","keyword":"도박","message":"금칙어 사용"}
  ],
  "suggested_body":"가족에게 책임 있는 만남을 약속드립니다...",
  "suggested_hashtags":["#책임분양","#반려가족","#방문상담"]
}
```

### BillingScheduler 상태전이

D+1 미납 → `subscriptions.status=OVERDUE` & `campaigns.status=PAUSED_BY_BILLING`

---

## 최종 전달 메모(개발팀 공지용, 복붙)

**지금부터 P0는 아래 3축만 개발합니다.**
(1) 회원 웹/앱 핵심 여정, (2) 정책·결제 엔진(+최소 어드민 UI), (3) 서버(API/DB/배치)

**램핑/TV Dash 고도화는 동결. 버그 대응만, 신규 개발 금지.**

**로그인 후 홈으로 이동하되, 스토어 미완성 시 광고 생성은 프런트/서버 모두 차단.**

**'계약서 적립' 기능은 보호 대상으로 현행 유지, 영향 변경 금지.**

**OpenAPI/DDL을 먼저 동결하고 구현 착수.**

**BillingScheduler로 D-2/D-1/D 알림 & D+1 미납 자동 정지/재개 연결.**

**최소 어드민 UI 3화면(매장/광고 목록, 승인·반려 상세)만 P0 범위.**

**DoD: 위 수용 기준 통과 + E2E 시나리오 녹화/문서화.**

