import { test, expect } from '@playwright/test';

test('온보딩: 가입→매장→플랜→펫→캠페인(클린)', async ({ page }) => {
  const email = `user_${Date.now()}@example.com`;
  const pw = 'Passw0rd!';

  // 1) 회원가입
  await page.goto('/signup');
  await page.getByPlaceholder('이메일').fill(email);
  await page.getByPlaceholder(/비밀번호/).fill(pw);
  await page.getByRole('button', { name: '가입하기' }).click();

  // 자동 로그인 후 /dashboard 도착을 보장
  await page.waitForURL(/\/dashboard/, { timeout: 10000 });

  // 2) 매장 등록
  await page.goto('/stores/new');
  await page.waitForSelector('input[placeholder="매장명"]', { timeout: 10000 });
  await page.getByPlaceholder('매장명').fill('테스트매장');
  await page.getByPlaceholder(/주소/).fill('서울시');
  await page.getByPlaceholder(/연락처|전화/).fill('02-0000-0000');
  await page.getByRole('button', { name: /등록|생성/ }).click();

  // 매장 등록 후 플랜 페이지로 이동 대기
  await page.waitForURL(/\/plans/, { timeout: 10000 });

  // 3) 플랜 선택 - 페이지가 로드될 때까지 대기
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  // 플랜 버튼이 나타날 때까지 대기
  const planButtons = page.getByRole('button', { name: /이 플랜으로/ });
  await planButtons.first().waitFor({ state: 'visible', timeout: 10000 });
  const count = await planButtons.count();
  expect(count).toBeGreaterThan(0);
  await planButtons.first().click();
  await page.waitForLoadState('networkidle');

  // 4) 펫 등록
  await page.goto('/pets');
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  // 페이지 구현에 따라 placeholder 라벨이 다를 수 있어 유연 매칭
  const nameInput = page.getByPlaceholder(/이름|반려동물 이름|Pet/i);
  await nameInput.waitFor({ state: 'visible', timeout: 10000 });
  await nameInput.fill('해피');
  await page.getByRole('button', { name: /등록|추가/ }).click();
  await page.waitForLoadState('networkidle');

  // 5) 클린 캠페인 생성
  await page.goto('/campaigns/new');
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  const campaignNameInput = page.getByPlaceholder(/캠페인명|제목/);
  await campaignNameInput.waitFor({ state: 'visible', timeout: 10000 });
  await campaignNameInput.fill('클린캠페인');
  const textInput = page.getByPlaceholder(/문구|카피|광고 문구/);
  await textInput.waitFor({ state: 'visible', timeout: 10000 });
  await textInput.fill('산책 가요!');
  await page.getByRole('button', { name: '생성' }).click();

  // 생성 후 /campaigns 도착
  await page.waitForURL(/\/campaigns/, { timeout: 10000 });
  await expect(page.getByText(/클린캠페인/)).toBeVisible({ timeout: 10000 });
});
