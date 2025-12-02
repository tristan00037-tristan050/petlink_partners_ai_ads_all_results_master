# PetLink Partners - WebApp

클라이언트용 프론트엔드 웹앱입니다.

## 구조

- `frontend/` - 메인 클라이언트 화면
- `web/` - v2.5 UI 시스템
- `index.html` - 통합 SPA 진입점
- `app-ui/` - App UI 컴포넌트

## 배포

### 정적 파일 서버 (예: Nginx)

```nginx
server {
    listen 80;
    server_name app.petlink.kr;
    root /path/to/webapp;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### Node.js serve 사용

```bash
npm install
npm start
```

## 환경 변수

웹앱은 API 서버 URL을 환경 변수로 받습니다:

```bash
export API_BASE_URL=https://api.petlink.kr
```

## API 엔드포인트

웹앱은 다음 API를 호출합니다:
- `/auth/*` - 인증
- `/advertiser/*` - 광고주 정보
- `/ads/*` - 광고 관리
- `/stores/*` - 매장 관리
- `/animals/*` - 동물 관리
- `/ads/billing/*` - 결제

## CORS

API 서버에서 `APP_ORIGIN` 환경 변수에 웹앱 도메인을 설정해야 합니다.
