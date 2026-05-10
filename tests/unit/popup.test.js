import { test, describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';

// We'll import popup.js
let popup;

describe('Popup UI Logic', () => {
  let dom;
  let window;
  let document;

  beforeEach(async () => {
    dom = new JSDOM(
      `
      <!DOCTYPE html>
      <html>
        <body>
          <div id="chat-container"></div>
          <div id="chat-log"></div>
          <form id="chat-form">
            <input id="chat-input" value="Hello AI" />
            <button type="submit">Send</button>
          </form>
        </body>
      </html>
    `,
      { url: 'http://localhost' }
    );

    window = dom.window;
    document = window.document;
    globalThis.window = window;
    globalThis.document = document;
    globalThis.HTMLElement = window.HTMLElement;
    globalThis.HTMLDivElement = window.HTMLDivElement;
    globalThis.Node = window.Node;

    // Mock fetch
    globalThis.fetch = mock.fn();

    // Mock gapi
    globalThis.gapi = {
      load: mock.fn((name, callback) => callback()),
      auth2: {
        init: mock.fn(),
        getAuthInstance: mock.fn(() => ({
          signIn: mock.fn(() => Promise.resolve()),
          currentUser: {
            get: mock.fn(() => ({
              getAuthResponse: mock.fn(() => ({
                id_token: 'fake-token',
              })),
            })),
          },
        })),
      },
    };

    // Import the module under test
    // To ensure fresh execution of top-level code if we wanted to, we'd need a cache buster
    // But for now let's just handle the fact it might have been called already
    if (!popup) {
      popup = await import(`../../src/popup.js?update=${Date.now()}`);
    }
  });

  afterEach(() => {
    mock.restoreAll();
  });

  it('should initialize the popup correctly', () => {
    // If it was already called during import, this might be the second call
    // or we can just verify it HAS been called.
    popup.initPopup();
    assert.ok(globalThis.gapi.load.mock.callCount() >= 1);
    assert.ok(globalThis.gapi.auth2.init.mock.callCount() >= 1);
  });

  it('should send a message successfully', async () => {
    const mockResponse = {
      choices: [{ text: 'Hello human!' }],
    };
    globalThis.fetch.mock.mockImplementationOnce(() =>
      Promise.resolve({
        json: () => Promise.resolve(mockResponse),
      })
    );

    await popup.sendMessage('Hello AI', 'fake-api-key');

    const chatLog = document.getElementById('chat-log');
    assert.ok(chatLog.textContent.includes('Hello human!'));
    assert.strictEqual(globalThis.fetch.mock.callCount(), 1);

    const fetchArgs = globalThis.fetch.mock.calls[0].arguments;
    assert.strictEqual(fetchArgs[0], 'https://api.openai.com/v1/engine/davinci-codex/completions');
    assert.strictEqual(fetchArgs[1].method, 'POST');
    assert.ok(fetchArgs[1].headers.Authorization.includes('fake-api-key'));
  });

  it('should handle form submission', async () => {
    const mockApiKeyResponse = { apiKey: 'real-api-key' };
    const mockChatResponse = { choices: [{ text: 'Response' }] };

    // First fetch for API key, second for chat message
    globalThis.fetch.mock.mockImplementation(url => {
      if (url.includes('getApiKey')) {
        return Promise.resolve({ json: () => Promise.resolve(mockApiKeyResponse) });
      }
      return Promise.resolve({ json: () => Promise.resolve(mockChatResponse) });
    });

    const event = {
      preventDefault: mock.fn(),
    };

    await popup.handleFormSubmit(event);

    assert.strictEqual(event.preventDefault.mock.callCount(), 1);
    const chatLog = document.getElementById('chat-log');
    // It should have both the user message and the response
    assert.ok(chatLog.textContent.includes('Hello AI'));
    assert.ok(chatLog.textContent.includes('Response'));
    assert.strictEqual(globalThis.fetch.mock.callCount(), 2);
  });

  it('should log error on fetch failure in sendMessage', async () => {
    mock.method(console, 'error', () => {});
    globalThis.fetch.mock.mockImplementationOnce(() => Promise.reject(new Error('Network error')));

    try {
      await popup.sendMessage('test', 'key');
    } catch (e) {
      // expected
    }

    assert.strictEqual(console.error.mock.callCount(), 1);
  });
});
