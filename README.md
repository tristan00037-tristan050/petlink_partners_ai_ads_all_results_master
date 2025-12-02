# PetLink Partners - 프로덕션 소스

실전 서비스 배포를 위한 분리된 소스 코드입니다.

## 구조

```
production/
├── webapp/          # 클라이언트 웹앱 (정적 파일)
├── server/          # 백엔드 API 서버 (Node.js)
├── admin/           # 관리자 대시보드 (정적 파일)
└── DEPLOYMENT_GUIDE.md  # 배포 가이드
```

## 빠른 시작

### 1. 웹앱
```bash
cd webapp
npm install
npm start
# http://localhost:3000
```

### 2. 서버
```bash
cd server
npm install
cp .env.example .env
# .env 파일 수정
npm start
# http://localhost:5902
```

### 3. 어드민
```bash
cd admin
npm install
npm start
# http://localhost:8000
```

## 배포

자세한 배포 가이드는 `DEPLOYMENT_GUIDE.md`를 참고하세요.

## 환경 변수

각 디렉토리의 `.env.example` 파일을 참고하여 `.env` 파일을 생성하세요.

## 보안

- 프로덕션 환경에서는 반드시 `.env` 파일의 비밀번호와 키를 변경하세요.
- HTTPS를 적용하세요.
- CORS 설정을 정확히 하세요.

## 지원

문제가 발생하면 각 디렉토리의 `README.md`를 참고하세요.
