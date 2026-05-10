import { test, expect, chromium } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pathToExtension = path.resolve(__dirname, '../../dist/ChatPTPanel-99-dev');

test.describe('ChatGPT Panel E2E Test', () => {
  let browserContext;
  let page;

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

  test('full flow: send message and receive mocked response', async () => {
    // 1. Get the background page or extension ID
    let [background] = browserContext.serviceWorkers();
    if (!background) {
      background = await browserContext.waitForEvent('serviceworker');
    }

    const extensionId = background.url().split('/')[2];
    const popupUrl = `chrome-extension://${extensionId}/popup.html`;

    page = await browserContext.newPage();

    // Mock Google Auth (gapi)
    await page.addInitScript(() => {
      window.gapi = {
        load: (name, cb) => {
          if (cb) cb();
        },
        auth2: {
          init: () => ({
            signIn: () => Promise.resolve(),
          }),
          getAuthInstance: () => ({
            signIn: () => Promise.resolve(),
            currentUser: {
              get: () => ({
                getAuthResponse: () => ({
                  id_token: 'mocked_id_token',
                }),
              }),
            },
          }),
        },
      };
    });

    // Mock Backend /getApiKey
    await page.route('**/getApiKey', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ apiKey: 'mocked_openai_api_key' }),
      });
    });

    // Mock OpenAI API
    await page.route('https://api.openai.com/v1/engine/davinci-codex/completions', async (route) => {
      const requestBody = route.request().postDataJSON();
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          choices: [
            {
              text: `Mocked response for: ${requestBody.prompt}`,
            },
          ],
        }),
      });
    });

    await page.goto(popupUrl);

    // Verify UI visibility
    const chatContainer = page.locator('#chat-container');
    const chatInput = page.locator('#chat-input');
    const chatForm = page.locator('#chat-form');

    await expect(chatContainer).toBeVisible();
    await expect(chatInput).toBeVisible();
    await expect(chatForm).toBeVisible();

    // 2. Simulate user typing and submitting
    const userMessage = 'Hello, AI!';
    await chatInput.fill(userMessage);
    await page.keyboard.press('Enter');

    // 3. Verify user message appears in chat log
    const userLogEntry = page.locator('#chat-log .user');
    await expect(userLogEntry).toHaveText(userMessage);

    // 4. Verify mocked AI response appears in chat log
    // The response doesn't have the .user class
    const aiLogEntry = page.locator('#chat-log div:not(.user)');
    await expect(aiLogEntry).toContainText(`Mocked response for: ${userMessage}`);
  });
});
