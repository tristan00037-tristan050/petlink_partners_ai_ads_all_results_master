import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  workers: 1, // 직렬 실행
  use: {
    baseURL: 'http://localhost:3003',
    headless: true,
    navigationTimeout: 60000,
    actionTimeout: 30000,
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
