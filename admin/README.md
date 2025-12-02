# PetLink Partners - Admin Dashboard

관리자 대시보드입니다.

## 구조

- `index.html` - 관리자 대시보드 메인
- `admin-ui/` - 관리자 UI 컴포넌트

## 배포

### 정적 파일 서버 (예: Nginx)

```nginx
server {
    listen 80;
    server_name admin.petlink.kr;
    root /path/to/admin;
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

어드민은 API 서버 URL을 환경 변수로 받습니다:

```bash
export API_BASE_URL=https://api.petlink.kr
export ADMIN_KEY=your-admin-key
```

## API 엔드포인트

어드민은 다음 API를 호출합니다:
- `/admin/*` - 모든 관리자 기능
- 헤더에 `X-Admin-Key` 필요

## CORS

API 서버에서 `ADMIN_ORIGIN` 환경 변수에 어드민 도메인을 설정해야 합니다.
