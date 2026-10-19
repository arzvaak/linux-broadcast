import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    const w = window as any;
    w.calls = [];
    w.mics = [{ id: 1, name: 'mic', description: 'Test microphone', isDefault: true }];
    w.service = { running: false, sourceName: null, intensity: .75, monitoring: false, monitorSinkName: null, effectMode: 'noise', vadEnabled: false, frameMs: 20 };
    w.background = { runInBackground: true, startAtLogin: false };
    w.__TAURI_INTERNALS__ = { invoke: async (cmd: string, args: any) => {
      w.calls.push(cmd);
      if (cmd === 'system_status') return { gpuName: 'RTX', architecture: 'sm_89', computeCapability: '8.9', modelReady: true, pluginReady: true, availableEffects: ['noise', 'studio_voice'] };
      if (cmd === 'list_microphones') return w.mics;
      if (cmd === 'list_outputs') return [{ name: 'headphones', description: 'Headphones', isDefault: true }];
      if (cmd === 'processing_status') {
        const snapshot = { ...w.service };
        if (w.holdNextStatus) { w.holdNextStatus = false; await new Promise(r => { w.releaseStatus = r; }); }
        return snapshot;
      }
      if (cmd === 'background_settings') return w.background;
      if (cmd === 'set_start_at_login') return w.background = { ...w.background, startAtLogin: args.enabled };
      if (cmd === 'set_run_in_background') return w.background = { ...w.background, runInBackground: args.enabled };
      if (w.delay) await new Promise(r => setTimeout(r, w.delay));
      if (w.fail) throw 'Test backend failure';
      if (cmd === 'start_processing') return w.service = { ...w.service, ...args, running: true };
      if (cmd === 'stop_processing') return w.service = { ...w.service, running: false, monitoring: false };
      if (cmd === 'set_monitoring') return w.service = { ...w.service, monitoring: args.enabled, monitorSinkName: args.sinkName };
      throw `Unexpected command: ${cmd}`;
    }};
  });
  await page.goto('/');
  await expect(page.locator('#gpu')).toHaveText('RTX');
});

test('missing saved intensity uses balanced defaults', async ({ page }) => {
  await expect(page.locator('#strength')).toHaveValue('75');
});

test('login toggle can be used repeatedly', async ({ page }) => {
  await page.locator('#settingsButton').click();
  await page.locator('#startAtLogin').click();
  await expect(page.locator('#startAtLogin')).toBeEnabled();
  await page.locator('#startAtLogin').click();
  await expect(page.locator('#startAtLogin')).toHaveAttribute('aria-pressed', 'false');
});

test('changing input while stopped stays stopped', async ({ page }) => {
  await page.locator('#microphone').selectOption('mic');
  expect(await page.evaluate(() => (window as any).calls.filter((c: string) => c === 'start_processing'))).toEqual([]);
});

test('expanded controls can be scrolled fully into view', async ({ page }) => {
  await page.locator('summary').click();
  await page.mouse.move(340, 500);
  await page.mouse.wheel(0, 650);
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);
  expect(await page.locator('#monitor').evaluate(el => { const r = el.getBoundingClientRect(); return r.bottom <= innerHeight && r.top >= 0; })).toBe(true);
});

test('device list refreshes and retains a disconnected selection', async ({ page }) => {
  await page.evaluate(() => { (window as any).mics = []; });
  await expect(page.locator('#microphone option:checked')).toContainText('disconnected', { timeout: 6000 });
  await page.evaluate(() => { (window as any).mics = [{ id: 42, name: 'mic', description: 'Test microphone', isDefault: true }, { id: 43, name: 'new', description: 'New microphone' }]; });
  await expect(page.locator('#microphone option')).toHaveCount(2, { timeout: 6000 });
  await expect(page.locator('#microphone')).toHaveValue('mic');
});

test('settings remain accessible while processing changes and repeated actions are guarded', async ({ page }) => {
  await page.evaluate(() => { (window as any).delay = 700; });
  await page.locator('#power').click();
  await expect(page.locator('#effect')).toBeDisabled();
  await page.locator('#settingsButton').click();
  await expect(page.locator('#settingsView')).toBeVisible();
  await page.locator('#settingsBack').click();
  await expect(page.locator('#power b')).toHaveText('Stop');
  await expect(page.locator('#effect')).toBeEnabled();
});

test('backend failures reconcile controls and allow retry', async ({ page }) => {
  await page.locator('#power').click();
  await page.evaluate(() => { (window as any).fail = true; });
  await page.locator('#effect').selectOption('studio_voice');
  await expect(page.locator('#notice')).toHaveText('Test backend failure');
  await expect(page.locator('#effect')).toHaveValue('noise');
  await expect(page.locator('#power')).toBeEnabled();
});

test('tuning, monitor and Stop invoke real control handlers', async ({ page }) => {
  await page.locator('#power').click();
  await page.locator('summary').click();
  await page.locator('#vad').click();
  await expect(page.locator('#vad')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#frameSize').selectOption('10');
  await page.locator('#resetTuning').click();
  await expect(page.locator('#frameSize')).toHaveValue('20');
  await page.locator('#monitor').click();
  await expect(page.locator('#monitor')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#power').click();
  await expect(page.locator('#power b')).toHaveText('Start');
});


test('a device poll started before Start cannot overwrite the completed action', async ({ page }) => {
  await page.evaluate(() => { (window as any).holdNextStatus = true; window.dispatchEvent(new Event('focus')); });
  await expect.poll(() => page.evaluate(() => typeof (window as any).releaseStatus)).toBe('function');
  await page.locator('#power').click();
  await expect(page.locator('#power b')).toHaveText('Stop');
  await page.evaluate(() => (window as any).releaseStatus());
  await page.waitForTimeout(150);
  expect(await page.locator('#power b').textContent()).toBe('Stop');
});

test('a monitor process exiting is reflected without resetting tuning gestures', async ({ page }) => {
  await page.locator('#power').click();
  await page.locator('#monitor').click();
  await expect(page.locator('#monitor')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#strength').evaluate((el: HTMLInputElement) => { el.value = '38'; el.dispatchEvent(new Event('input')); });
  await page.evaluate(() => { (window as any).service.monitoring = false; window.dispatchEvent(new Event('focus')); });
  await expect(page.locator('#monitor')).toHaveAttribute('aria-pressed', 'false', { timeout: 6000 });
  await expect(page.locator('#strength')).toHaveValue('38');
});

test('background toggle can be used repeatedly', async ({ page }) => {
  await page.locator('#settingsButton').click();
  await page.locator('#runInBackground').click();
  await expect(page.locator('#runInBackground')).toBeEnabled();
  await expect(page.locator('#runInBackground')).toHaveAttribute('aria-pressed', 'false');
  await page.locator('#runInBackground').click();
  await expect(page.locator('#runInBackground')).toHaveAttribute('aria-pressed', 'true');
});
