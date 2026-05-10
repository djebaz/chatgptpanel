import { test, expect, chromium } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pathToExtension = path.resolve(__dirname, '../../dist/ChatPTPanel-99-dev');

test.describe('ChatGPT Panel E2E Test', () => {
  let browserContext;

  test.beforeAll(async () => {
    browserContext = await chromium.launchPersistentContext('', {
      headless: false, // Extensions only work in headful mode
      args: [
        `--disable-extensions-except=${pathToExtension}`,
        `--load-extension=${pathToExtension}`,
      ],
    });
  });

  test.afterAll(async () => {
    await browserContext.close();
  });

  test('extension popup allows opening chatgpt', async () => {
    // 1. Get the background service worker to extract the extension ID
    let [background] = browserContext.serviceWorkers();
    if (!background) {
      background = await browserContext.waitForEvent('serviceworker');
    }

    const extensionId = background.url().split('/')[2];
    const popupUrl = `chrome-extension://${extensionId}/popup.html`;

    // 2. Open the popup in a new page (simulating clicking the action icon)
    const popupPage = await browserContext.newPage();
    await popupPage.goto(popupUrl);

    // 3. Verify the popup loads and has the expected buttons
    await expect(popupPage.locator('#btn-popup')).toBeVisible();
    await expect(popupPage.locator('#btn-sidepanel')).toBeVisible();
    await expect(popupPage.locator('#btn-tab')).toBeVisible();

    // 4. Click the "Open in Window" button and wait for the new popup to be created
    const newPagePromise = browserContext.waitForEvent('page');
    await popupPage.locator('#btn-popup').click();
    
    // 5. Wait for the new window/page to open
    const newPage = await newPagePromise;
    await newPage.waitForLoadState('domcontentloaded');

    // 6. Verify the URL is correct
    expect(newPage.url()).toContain('chatgpt.com');
  });
});
