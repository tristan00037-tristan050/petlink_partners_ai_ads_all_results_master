import { test, expect } from '@playwright/test';

test('미인증 보호페이지 접근 → /login 리다이렉트', async ({ page }) => {
  await page.context().clearCookies();
  await page.goto('/campaigns');
  await expect(page).toHaveURL(/\/login/);
});

