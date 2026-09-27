import { expect, test } from '@playwright/test';

test('pairs, reads output, pauses paging, and confirms a prompt', async ({ page }) => {
  await page.goto('/#token=test-pairing-token-for-browser');
  await expect(page.locator('#connection')).toContainText('Orca 接続済み');
  expect(page.url()).not.toContain('token=');
  await page.getByRole('button', { name: /Even G2 アプリの実装/ }).click();
  await expect(page.locator('#glass-body')).toContainText('実機との接続確認');
  await page.getByRole('button', { name: '前のページ' }).click();
  await expect(page.locator('#follow')).toHaveAttribute('aria-pressed', 'false');
  await expect(page.locator('#glass-body')).toContainText('セッション一覧');
  await page.locator('#follow').click();
  await expect(page.locator('#glass-body')).toContainText('実機との接続確認');
  let sends = 0;
  await page.route('**/api/sessions/demo/send', async (route) => {
    sends++;
    await route.continue();
  });
  await page.getByRole('button', { name: '進捗を聞く' }).click();
  await expect(page.locator('#confirmation')).toBeVisible();
  expect(sends).toBe(0);
  await page.locator('#confirm-action').click();
  await expect(page.locator('#notice')).toContainText('実行開始を確認');
  expect(sends).toBe(1);
  await expect(page.locator('#confirmation')).toBeHidden();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await page.screenshot({
    path: `test-results/${test.info().project.name}-app.png`,
    fullPage: true,
  });
});

test('shows authentication errors and can recover through connection settings', async ({
  page,
}) => {
  await page.goto('/#token=wrong-token');
  await expect(page.locator('#notice')).toContainText('トークンを確認');
  await page.getByRole('button', { name: '接続設定', exact: true }).click();
  await page.getByLabel('ペアリング用トークン').fill('test-pairing-token-for-browser');
  await page.getByRole('button', { name: '接続する', exact: false }).click();
  await expect(page.locator('#connection')).toContainText('Orca 接続済み');
});

test('a cancelled stop never reaches the bridge', async ({ page }) => {
  await page.goto('/#token=test-pairing-token-for-browser');
  await page.getByRole('button', { name: /Even G2 アプリの実装/ }).click();
  let stops = 0;
  await page.route('**/api/sessions/demo/stop', async (route) => {
    stops++;
    await route.continue();
  });
  await page.locator('#stop').click();
  await expect(page.locator('#confirmation')).toBeVisible();
  await page.getByRole('button', { name: 'キャンセル', exact: true }).click();
  await expect(page.locator('#confirmation')).toBeHidden();
  expect(stops).toBe(0);
});
