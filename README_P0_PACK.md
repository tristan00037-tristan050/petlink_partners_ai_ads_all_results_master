# P0 Directive Pack 사용 가이드

## 파일 위치

P0 Directive Pack은 다음 경로에 있습니다:
- **디렉토리**: `extracted/production/p0_directive_pack/`
- **압축 파일**: `extracted/production/p0_directive_pack.tar.gz` (또는 `.zip`)

## 빠른 시작

### 1. 디렉토리로 직접 이동

```bash
cd extracted/production/p0_directive_pack
```

### 2. 압축 파일이 필요한 경우

```bash
cd extracted/production
tar -xzf p0_directive_pack.tar.gz -C p0_directive_pack
```

### 3. 서버 스텁 실행

```bash
cd p0_directive_pack/server_stubs/express
npm install
node app.js  # http://localhost:5903
```

### 4. DDL 적용

```bash
psql -d petlink -f p0_directive_pack/migrations/20251117_p0_core.sql
```

## 구성 파일

- `docs/README_P0_Directive_Final.md` - P0 개발 지침
- `openapi/openapi_p0.yaml` - API 스펙
- `migrations/20251117_p0_core.sql` - DDL
- `policy/policy_ruleset.example.json` - 정책 룰
- `server_stubs/express/app.js` - 서버 스텁

## 참고

현재 작업 디렉토리에서:
- `extracted/production/p0_directive_pack/` 디렉토리가 이미 존재합니다
- 압축 해제 없이 바로 사용 가능합니다
