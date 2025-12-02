import { test, expect } from '@playwright/test';

test('정책 차단 피드백 노출', async ({ page }) => {
  // 0) 로그인 (이미 계정이 있다면 재사용, 없으면 온보딩 스펙 이후 실행)
  const email = process.env.E2E_EMAIL || `user_${Date.now()}@example.com`;
  const pw = process.env.E2E_PASSWORD || 'Passw0rd!';

  // 계정이 없을 수 있으니, 로그인 실패 시 가입 시도 → 다시 로그인
  await page.goto('/login');
  await page.getByPlaceholder('이메일').fill(email);
  await page.getByPlaceholder(/비밀번호/).fill(pw);
  await page.getByRole('button', { name: '로그인' }).click();
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  
  if ((await page.url()).includes('/login')) {
    // 가입
    await page.goto('/signup');
    await page.getByPlaceholder('이메일').fill(email);
    await page.getByPlaceholder(/비밀번호/).fill(pw);
    await page.getByRole('button', { name: '가입하기' }).click();
    await page.waitForURL(/\/dashboard/, { timeout: 10000 });
  }

  // 1) 최소 조건: 매장/플랜이 없다면 빠르게 보강
  await page.goto('/stores/new');
  const nameInput = page.getByPlaceholder('매장명');
  if (await nameInput.isVisible({ timeout: 5000 }).catch(() => false)) {
    await nameInput.fill('정책테스트매장');
    await page.getByPlaceholder(/주소/).fill('서울시');
    await page.getByPlaceholder(/연락처|전화/).fill('02-0000-0000');
    await page.getByRole('button', { name: /등록|생성/ }).click();
    await page.waitForLoadState('networkidle', { timeout: 10000 });
    
    await page.goto('/plans');
    await page.waitForLoadState('networkidle', { timeout: 10000 });
    const planBtns = page.getByRole('button', { name: /이 플랜으로/ });
    const btnCount = await planBtns.count();
    if (btnCount > 0) {
      await planBtns.first().waitFor({ state: 'visible', timeout: 10000 });
      await planBtns.first().click();
      await page.waitForLoadState('networkidle', { timeout: 10000 });
    }
  }

  // 2) 정책 차단 캠페인 생성
  await page.goto('/campaigns/new');
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  const campaignNameInput = page.getByPlaceholder(/캠페인명|제목/);
  await campaignNameInput.waitFor({ state: 'visible', timeout: 10000 });
  await campaignNameInput.fill('차단캠페인');
  const textInput = page.getByPlaceholder(/문구|카피|광고 문구/);
  await textInput.waitFor({ state: 'visible', timeout: 10000 });
  await textInput.fill('무료 당첨 보장!');
  await page.getByRole('button', { name: '생성' }).click();

  // 3) UI에서 정책 피드백이 보이는지 확인
  // 정책 차단 메시지가 표시되는지 확인 (에러 영역 또는 정책 평가 영역)
  await expect(
    page.getByText(/정책 차단|금칙어|BLOCKED|문구를 수정해 주세요/i)
  ).toBeVisible({ timeout: 10000 });
});
