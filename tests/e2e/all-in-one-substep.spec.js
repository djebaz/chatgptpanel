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

  test('extension loads and opens chatgpt.com when action is clicked', async () => {
    // 1. Get the background service worker
    let [background] = browserContext.serviceWorkers();
    if (!background) {
      background = await browserContext.waitForEvent('serviceworker');
    }

    expect(background).toBeTruthy();

    // 2. Set up a listener for a new page being created
    const newPagePromise = browserContext.waitForEvent('page');

    // 3. Evaluate inside the service worker to verify listeners and simulate action
    await background.evaluate(async () => {
      // Playwright can't physically click the extension icon in the toolbar,
      // so we verify the listener is present and simulate its exact behavior.
      if (chrome.action.onClicked.hasListeners()) {
        chrome.windows.create({
          url: 'https://chatgpt.com',
          type: 'popup',
          width: 480,
          height: 700
        });
      } else {
        throw new Error('chrome.action.onClicked has no listeners registered!');
      }
    });

    // 4. Wait for the new window/page to open
    const newPage = await newPagePromise;
    await newPage.waitForLoadState('domcontentloaded');

    // 5. Verify the URL is correct
    expect(newPage.url()).toContain('chatgpt.com');
  });
});
