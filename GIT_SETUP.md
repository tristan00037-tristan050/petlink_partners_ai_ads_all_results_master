# GitHub 저장소 연동 가이드

## 현재 상태
- ✅ 패치 적용 완료 (`extracted/production`에 적용됨)
- ✅ `.gitignore` 파일 생성 완료
- ⏳ GitHub 저장소 연동 필요

## 실행 방법

### 방법 1: 스크립트 실행 (권장)

```bash
cd "/Users/atlink/Desktop/파트너스 공고플랫폼/petlink_partners_ai_ads_all_results_master/extracted/production"
bash setup_git.sh
```

### 방법 2: 수동 실행

다음 명령어를 순서대로 실행하세요:

```bash
# 1. 디렉토리 이동
cd "/Users/atlink/Desktop/파트너스 공고플랫폼/petlink_partners_ai_ads_all_results_master/extracted/production"

# 2. Git 저장소 초기화
git init

# 3. 원격 저장소 연결
git remote add origin https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master.git

# 4. 파일 추가
git add .

# 5. 초기 커밋 생성
git commit -m "Initial commit: PetLink Partners AI Ads Platform

- 매장 등록 페이지: ID 추출 보강 + submit 버튼 testid 부여
- 온보딩 테스트: 등록 후 테스트가 /plans로 주도 이동
- 정책 차단 테스트: 동일 패턴 적용
- 전체 프로덕션 소스 코드 포함"

# 6. 브랜치 이름 설정
git branch -M main

# 7. GitHub에 푸시
git push -u origin main
```

## 주의사항

1. **인증 필요**: GitHub에 푸시하려면 인증이 필요합니다.
   - Personal Access Token (PAT) 사용 권장
   - 또는 SSH 키 설정 후 `git@github.com:...` 형식 사용

2. **저장소 상태**: GitHub 저장소가 비어있어야 합니다.
   - 기존 내용이 있다면 `git push -u origin main --force` 사용 (주의!)

3. **파일 크기**: 대용량 파일이 포함되어 있을 수 있습니다.
   - `.gitignore`에 의해 `node_modules`, `.next` 등은 제외됩니다.

## 적용된 패치 내용

### 1. 매장 등록 페이지 (`apps/owner/app/stores/new/page.tsx`)
- ✅ ID 추출 로직 보강 (여러 응답 형태 지원)
- ✅ Submit 버튼에 `data-testid="store-submit"` 추가
- ✅ FormData 기반으로 변경

### 2. 온보딩 테스트 (`tests/e2e/onboarding.spec.ts`)
- ✅ 매장 등록 후 테스트가 주도적으로 `/plans`로 이동
- ✅ `getByTestId('store-submit')` 사용

### 3. 정책 차단 테스트 (`tests/e2e/policy-block.spec.ts`)
- ✅ 동일한 패턴 적용

## 확인 방법

푸시 완료 후 다음 URL에서 확인할 수 있습니다:
https://github.com/tristan00037-tristan050/petlink_partners_ai_ads_all_results_master

