import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  use: { baseURL: 'http://127.0.0.1:1420', viewport: { width: 680, height: 740 } },
  webServer: { command: 'npm run dev -- --host 127.0.0.1 --port 1420', url: 'http://127.0.0.1:1420', reuseExistingServer: true },
});
