# P0 핫픽스 패키지

## 구성

- `docs/AI_P0_Directive.md` - P0 개발 지침 요약
- `api/openapi.yaml` - P0 API 스켈레톤
- `db/ddl.sql` - PostgreSQL DDL
- `seed/plans.json` - 요금제 시드 데이터
- `server_stub/node/index.js` - Express 스텁 서버
- `scripts/test_api.sh` - 스텁 동작 검증 스크립트

## 사용 방법

### 1. 개발 모드 (스텁)

```bash
unzip p0_hotfix_pack.zip -d p0_hotfix_pack
cd p0_hotfix_pack/server_stub/node
npm init -y
npm i express
node index.js
# 스텁 기동: http://localhost:3800
```

### 2. 테스트

```bash
cd p0_hotfix_pack/scripts
bash test_api.sh
# [1] Health / [2] Plans / [3] Signup / [4] Campaign Guard(400) 확인
```

### 3. 운영 복귀

1. **DB/DDL/시드 정리**
   ```bash
   psql "$DATABASE_URL" -f db/ddl.sql
   # plans 시드 입력 (seed/plans.json 기준)
   ```

2. **서버 재기동 & 에러 스택 확인**
   ```bash
   cd <your-repo>/extracted/production/server
   node app_p0.js
   # 로그 확인
   ```

3. **라우트 구현/예외처리 확인**
   - `/plans`: DB 조회 실패 시 명확한 에러 로깅
   - `/auth/signup`: email Unique 제약, 비밀번호 해시, 필드 검증

## 목적

실제 DB가 아직 정리되지 않은 상태에서도 `/plans`, `/auth/signup` 경로를 즉시 정상 동작으로 만드는 연동 확인용 스텁입니다.

운영 복귀는 "P0 API 복구 지시안" 절차로 진행해 주세요.

