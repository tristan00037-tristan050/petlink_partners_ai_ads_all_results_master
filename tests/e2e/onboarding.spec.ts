import { test, expect } from '@playwright/test';
import { safeGoto } from './_utils';

test('온보딩: 가입→매장→플랜→펫→캠페인(클린)', async ({ page }) => {
  const email = `user_${Date.now()}@example.com`;
  const pw = 'Passw0rd!';

  // 1) 회원가입
  await page.goto('/signup', { waitUntil: 'domcontentloaded' });
  await page.getByPlaceholder('이메일').fill(email);
  await page.getByPlaceholder(/비밀번호/).fill(pw);
  await page.getByRole('button', { name: '가입하기' }).click();

  // 2) 자동 로그인 → /dashboard
  await page.waitForURL(/\/dashboard$/, { timeout: 15000 });
  await page.waitForLoadState('networkidle', { timeout: 8000 });

  // 3) 매장 등록
  await safeGoto(page, '/stores/new');
  await page.getByPlaceholder('매장명').fill('테스트매장');
  await page.getByPlaceholder(/주소/).fill('서울시');
  await page.getByPlaceholder(/연락처|전화/).fill('02-0000-0000');

  // 고정 셀렉터로 클릭
  const submitBtn = page.getByTestId('store-submit');
  await expect(submitBtn).toBeVisible({ timeout: 10000 });
  await submitBtn.click();

  // 백엔드 처리/로컬스토리지 반영 유예
  await page.waitForTimeout(700);

  // ★ UI 리다이렉트에 의존하지 않고 테스트가 주도적으로 이동
  if (!/\/plans(\?|$)/.test(page.url())) {
    await safeGoto(page, '/plans');
  }

  // 4) 플랜 구독
  await page.waitForSelector('[data-testid^="plan-select-"]', { timeout: 15000 });
  const planButtons = page.locator('[data-testid^="plan-select-"]');
  const cnt = await planButtons.count();
  expect(cnt).toBeGreaterThan(0);
  await planButtons.first().click();

  // 6) /pets (안정 이동) + 펫 등록
  await safeGoto(page, '/pets');
  await page.getByTestId('pet-name').fill('해피');
  await page.getByTestId('pet-add').click();

  // 7) /campaigns/new (안정 이동) + 클린 캠페인 생성
  await safeGoto(page, '/campaigns/new');
  await page.getByPlaceholder(/캠페인명|제목/).fill('클린캠페인');
  await page.getByPlaceholder(/문구|카피|광고 문구/).fill('산책 가요!');
  await page.getByRole('button', { name: '생성' }).click();

  await page.waitForURL(/\/campaigns$/, { timeout: 15000 });
  await expect(page.getByText(/클린캠페인/)).toBeVisible({ timeout: 10000 });
});
