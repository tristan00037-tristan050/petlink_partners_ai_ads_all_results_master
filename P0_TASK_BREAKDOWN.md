# P0 개발 작업 분해 (Task Breakdown)

## Sprint 0 (3일) - 기반 구축

### OpenAPI 정의
- [ ] `auth.yaml` - 인증 API 스키마
- [ ] `stores.yaml` - 매장 API 스키마
- [ ] `plans.yaml` - 요금제 API 스키마
- [ ] `campaigns.yaml` - 캠페인 API 스키마
- [ ] `admin.yaml` - 관리자 API 스키마

### DDL 마이그레이션
- [ ] `store_plan_subscriptions` 테이블 생성
- [ ] `policy_violations` 테이블 생성
- [ ] `campaigns` 테이블 상태 열거 확장 (REJECTED_BY_POLICY, PENDING_REVIEW, PAUSED_BY_BILLING)
- [ ] 인덱스 추가 (검색 성능)

### 프런트엔드 기반
- [ ] 라우팅 구조 설정 (SPA)
- [ ] 상태 관리 구조 (로컬 스토리지/상태)
- [ ] 공통 컴포넌트 (헤더, 버튼, 폼)
- [ ] API 클라이언트 래퍼

### PolicyEngine 인터페이스
- [ ] PolicyEngine 모듈 구조 정의
- [ ] 결과 스키마 타입 정의
- [ ] 상태 전이 로직 인터페이스

---

## Sprint 1 (7일) - 핵심 기능 구현

### 회원 웹/앱
- [ ] 홈 대시보드 (매장 등록 여부, 플랜 요약, 최근 광고, 배너)
- [ ] My Store 페이지 (등록/수정, 필수 필드 검증)
- [ ] 요금제 선택 UI (S/M/L)
- [ ] 반려동물 선택/등록
- [ ] 사진/영상 업로드 (1~5장, 영상 옵션)
- [ ] AI 카피 생성 UI (필수)
- [ ] 미리보기/편집
- [ ] 채널 선택 (체크박스)
- [ ] 광고 생성 API 연동
- [ ] 광고 관리 리스트
- [ ] 광고 상세/상태 변경 (시작/일시중지/종료)

### PolicyEngine 구현
- [ ] 룰 기반 필터 (금칙어 검증)
- [ ] AI 심사 인터페이스 (텍스트 중심)
- [ ] `policy_violations` 기록 로직
- [ ] 브랜드 세이프티 검사
- [ ] 제안 문구 생성
- [ ] 상태 전이 로직 (DRAFT → SUBMITTED → APPROVED/REJECTED_BY_POLICY/PENDING_REVIEW)

### 어드민 UI
- [ ] 매장 목록 (검색, 필터, 승인/정지)
- [ ] 광고 목록 (검색, 필터, 상세 링크)
- [ ] 광고 승인/반려 상세 (콘텐츠 미리보기, policy_violations 리스트, 승인/반려 액션)

### 서버 API
- [ ] `POST /auth/signup`
- [ ] `POST /auth/login`
- [ ] `GET /auth/me`
- [ ] `GET /stores/me`
- [ ] `PUT /stores/me`
- [ ] `GET /plans`
- [ ] `GET /stores/me/plan`
- [ ] `POST /stores/me/plan`
- [ ] `POST /campaigns` (스토어 미완성 검증 포함)
- [ ] `GET /campaigns`
- [ ] `GET /campaigns/{id}`
- [ ] `PATCH /campaigns/{id}/pause|resume|stop|change-pet`
- [ ] `GET /admin/stores`
- [ ] `PATCH /admin/stores/{id}/status`
- [ ] `GET /admin/campaigns`
- [ ] `GET /admin/campaigns/{id}`
- [ ] `PATCH /admin/campaigns/{id}/approve`
- [ ] `PATCH /admin/campaigns/{id}/reject`

---

## Sprint 2 (7일) - 결제/배치/완성

### BillingScheduler
- [ ] 크론 작업 설정 (일 1회)
- [ ] D-2/D-1/D 예정 알림 로직
- [ ] D+1 미납 감지 및 상태 변경 (OVERDUE, PAUSED_BY_BILLING)
- [ ] 결제 완료 후 자동 재개 로직
- [ ] 배치 테스트

### 이미지 1차 필터
- [ ] 형식 검증 (JPG, PNG)
- [ ] 용량 검증
- [ ] 노출 감지 (기본)

### 어드민 승인/반려
- [ ] 승인 플로우 완성
- [ ] 반려 플로우 완성 (코멘트)
- [ ] 감사 로그 기록

### E2E 테스트
- [ ] 회원 가입 → 매장 등록 → 요금제 선택 → 광고 생성 → AI 카피 → 채널 선택 → 생성 완료
- [ ] 정책 검증 시나리오 (금칙어, AI 점수)
- [ ] 결제 미납 시나리오 (D+1 자동 정지)
- [ ] 결제 완료 시나리오 (자동 재개)
- [ ] 어드민 승인/반려 시나리오

### 성능 최적화
- [ ] 검색/필터 200ms 응답 (인덱스, 캐시)
- [ ] 프런트 로딩 최적화

---

## RC/릴리즈 (2일) - 하드닝/문서화

### 보안
- [ ] Security Headers 최종 확인
- [ ] CORS 설정 최종 확인
- [ ] 인증/인가 검증

### 문서화
- [ ] OpenAPI 문서 완성
- [ ] 운영 가이드 (배치 스케줄, 롤백, 알림 문구)
- [ ] 정책 로그 해석법
- [ ] QA 스크립트 (cURL/HTTPie)

### 데모 준비
- [ ] E2E 시나리오 녹화
- [ ] 데모 환경 구성

---

## 동결 항목 (개발 금지)

### 램핑/TV Dash
- ❌ 75%/100% 신규 승격 스크립트
- ❌ 램핑 알고리즘/지표 튜닝
- ❌ TV/램핑 전용 대시보드
- ❌ 고급 알림/자동 롤백 추가

**유지**: golive.sh, promote_*, backout_*, monitor_50pct_60min.sh, check_24h_metrics.sh (버그 대응만)

### 보호 대상
- ✅ 계약서 적립 기능 (현행 유지, 변경 금지)

---

## 우선순위

1. **P0 (즉시 개발)**: 위 작업 항목
2. **P1 (추후)**: PG 연동, 이메일/SMS 알림, 이미지/영상 고급 모더레이션
3. **P2~P3 (보류)**: 정책 시뮬레이터, 고급 RBAC, 통합 대시보드, 외부 알림 연동

