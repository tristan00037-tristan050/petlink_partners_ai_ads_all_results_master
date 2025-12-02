# P0 개발 지침 요약

## P0 스코프

### 회원 웹/앱
- 가입/로그인 → My Store 등록/수정 → 요금제 선택 → 반려동물/이미지/영상 업로드 → AI 카피 생성 → 노출 매체 선택 → 광고 생성/관리/상태 변경

### 본사 어드민
- 룰 기반 금칙어/필수값 검증 + AI 콘텐츠 심사
- 브랜드 세이프티/네거티브 키워드 검사 + 안전 문구 자동 제안
- 월 결제 상태 기반 제어
- 최소 관리 UI (매장/광고 리스트·검색·필터, 승인/반려)

### 서버
- 엔티티: users, stores, plans, store_plan_subscriptions, pets, campaigns, creatives, policy_violations
- OpenAPI 우선 확정 → 구현 → 배치 (BillingScheduler)

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
- 계약서 적립 기능 (보호 대상)

