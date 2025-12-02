import { expect, Page } from '@playwright/test';

export async function signupAndLogin(page: Page) {
  const email = `test+${Date.now()}@example.com`;
  const pass  = 'Passw0rd!';

  await page.goto('/signup', { waitUntil: 'domcontentloaded' });
  await page.getByPlaceholder(/이메일/i).fill(email);
  await page.getByPlaceholder(/비밀번호/i).fill(pass);
  await page.getByRole('button', { name: /가입/i }).click();
  await page.waitForURL(/\/dashboard/, { timeout: 15000 });

  return { email, pass };
}

