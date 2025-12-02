# Owner Portal

분양매장 오너용 웹 포털 (Next.js 스켈레톤)

## 시작하기

```bash
npm install
npm run dev
```

## 환경변수

`.env.local` 파일에 다음 설정:

```
NEXT_PUBLIC_API_BASE=http://localhost:5903
```

## 주요 기능

- 로그인 (`/login`)
- 대시보드 (`/dashboard`)
  - 내 정보 조회
  - 매장 목록 조회

## 주의사항

- 현재는 로컬스토리지에 토큰 저장 (운영 전환 시 httpOnly 쿠키/프록시 권장)
- API 베이스 URL은 환경변수로 설정 필요

