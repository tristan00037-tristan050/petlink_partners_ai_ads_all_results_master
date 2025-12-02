import { test, expect } from '@playwright/test';

const OWNER = process.env.OWNER_BASE || 'http://localhost:3003';
const API   = process.env.API_BASE   || 'http://localhost:5903';

function uniq(prefix='e2e'){ return `${prefix}_${Date.now()}@example.com`; }

test('P0 여정 7단계 UI 완주', async ({ page, context }) => {
  // 0) 테스트 계정 준비(백엔드 공개 API 활용, UI 회원가입 미노출 가정)
  const email = uniq(); const password = 'Passw0rd!';
  const resp = await page.request.post(`${API}/auth/signup`, {
    data: { email, password, tenant:'default' },
    headers: { 'content-type':'application/json' }
  });
  expect(resp.ok()).toBeTruthy();

  // 1) 로그인
  await page.goto(`${OWNER}/login`);
  await page.getByPlaceholder('이메일').fill(email);
  await page.getByPlaceholder('비밀번호').fill(password);
  await Promise.all([
    page.waitForURL(/dashboard/, { timeout: 10000 }),
    page.getByRole('button', { name:'로그인' }).click()
  ]);
  expect(page.url()).toMatch(/dashboard/);

  // 2) 매장 등록
  await page.goto(`${OWNER}/stores/new`);
  await page.waitForSelector('input[placeholder="매장명"]', { timeout: 10000 });
  await page.getByPlaceholder('매장명').fill('E2E Store');
  await page.getByPlaceholder(/주소/).fill('Seoul');
  await page.getByPlaceholder(/연락처|전화/).fill('02-0000-0000');
  page.on('dialog', d => d.accept());
  await page.getByRole('button', { name: /등록|생성/ }).click();
  await page.waitForLoadState('networkidle', { timeout: 10000 });

  // 3) 요금제 구독
  await page.goto(`${OWNER}/plans`);
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  // 플랜 버튼이 나타날 때까지 대기
  const btns = page.getByRole('button', { name: /이 플랜으로/ });
  await btns.first().waitFor({ state: 'visible', timeout: 10000 });
  const count = await btns.count();
  expect(count).toBeGreaterThan(0);
  await btns.first().click();
  await page.waitForLoadState('networkidle', { timeout: 10000 });

  // 4) 반려동물 등록
  await page.goto(`${OWNER}/pets`);
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  const nameInput = page.getByPlaceholder(/이름|반려동물 이름|Pet/i);
  await nameInput.waitFor({ state: 'visible', timeout: 10000 });
  await nameInput.fill('Mango');
  await page.getByRole('button', { name: /등록|추가/ }).click();
  await expect(page.getByText(/Mango/)).toBeVisible({ timeout: 10000 });

  // 5) 캠페인 생성(클린 텍스트)
  await page.goto(`${OWNER}/campaigns/new`);
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  const campaignNameInput = page.getByPlaceholder(/캠페인명|제목/);
  await campaignNameInput.waitFor({ state: 'visible', timeout: 10000 });
  await campaignNameInput.fill('E2E Campaign');
  const textInput = page.getByPlaceholder(/문구|카피|광고 문구/);
  await textInput.waitFor({ state: 'visible', timeout: 10000 });
  await textInput.fill('클린 텍스트');
  await page.getByRole('button', { name: '생성' }).click();

  // 목록 새로고침 후 존재 확인
  await page.waitForURL(/\/campaigns/, { timeout: 10000 });
  await expect(page.locator('li', { hasText: 'E2E Campaign' })).toBeVisible({ timeout: 10000 });

  // 6) 활성/일시중지/종료
  const row = page.locator('li', { hasText: 'E2E Campaign' });
  page.on('dialog', d => d.accept());
  await row.getByRole('button', { name: '활성' }).click();
  await page.waitForTimeout(400);
  await row.getByRole('button', { name: '일시중지' }).click();
  await page.waitForTimeout(400);
  await row.getByRole('button', { name: '정지' }).click();

  // 7) 인보이스 조회
  await page.goto(`${OWNER}/billing/invoices`);
  await page.waitForLoadState('networkidle', { timeout: 10000 });
  // 인보이스가 없을 수도 있으므로 화면 렌더링만 확인
  await expect(page.getByText(/인보이스/)).toBeVisible({ timeout: 10000 });

  // 보안 확인: 로컬스토리지에 토큰 흔적 없음
  const lsKeys = await page.evaluate(() => Object.keys(window.localStorage));
  expect(lsKeys.length === 0 || !lsKeys.some(k => /token|auth|jwt/i.test(k))).toBeTruthy();
});
