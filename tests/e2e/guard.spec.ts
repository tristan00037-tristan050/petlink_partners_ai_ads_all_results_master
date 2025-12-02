import { test, expect } from '@playwright/test';

test('미인증 보호페이지 접근 → /login 리다이렉트', async ({ page, context }) => {
  await context.clearCookies();
  await page.addInitScript(() => { localStorage.clear(); sessionStorage.clear(); });

  await page.goto('/campaigns', { waitUntil: 'domcontentloaded' });

  // SSR 미들웨어가 즉시 /login으로 보냄
  await expect(page).toHaveURL(/\/login(\?|$)/, { timeout: 15000 });
});
