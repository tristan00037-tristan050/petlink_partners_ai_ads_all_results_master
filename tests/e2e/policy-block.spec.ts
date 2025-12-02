import { test, expect } from '@playwright/test';
import { safeGoto } from './_utils';

test('정책 차단 피드백 노출', async ({ page }) => {
  const email = `user_${Date.now()}@example.com`;
  const pw = 'Passw0rd!';

  // 1) 회원가입 & 자동 로그인
  await page.goto('/signup', { waitUntil: 'domcontentloaded' });
  await page.getByPlaceholder('이메일').fill(email);
  await page.getByPlaceholder(/비밀번호/).fill(pw);
  await page.getByRole('button', { name: '가입하기' }).click();

  await page.waitForURL(/\/dashboard$/, { timeout: 15000 });
  await page.waitForLoadState('networkidle', { timeout: 8000 });

  // 3) 매장 등록
  await safeGoto(page, '/stores/new');
  await page.getByPlaceholder('매장명').fill('정책매장');
  await page.getByPlaceholder(/주소/).fill('서울');
  await page.getByPlaceholder(/연락처|전화/).fill('02-0000-0000');

  const submitBtn = page.getByTestId('store-submit');
  await expect(submitBtn).toBeVisible({ timeout: 10000 });
  await submitBtn.click();

  await page.waitForTimeout(700);

  if (!/\/plans(\?|$)/.test(page.url())) {
    await safeGoto(page, '/plans');
  }

  // 4) 플랜 구독
  await page.waitForSelector('[data-testid^="plan-select-"]', { timeout: 15000 });
  await page.getByRole('button', { name: /이 플랜으로/ }).first().click();

  // 4) /pets
  await safeGoto(page, '/pets');
  await page.getByTestId('pet-name').fill('해피');
  await page.getByTestId('pet-add').click();

  // 5) /campaigns/new → 금칙어 포함 생성 → 차단 메시지 확인
  await safeGoto(page, '/campaigns/new');
  await page.getByPlaceholder(/캠페인명|제목/).fill('차단캠페인');
  await page.getByPlaceholder(/문구|카피|광고 문구/).fill('무료 당첨 보장!');
  await page.getByRole('button', { name: '생성' }).click();

  await expect(page.getByTestId('policy-block-msg')).toBeVisible({ timeout: 15000 });
});
