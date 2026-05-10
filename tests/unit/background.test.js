import { test, describe, it, mock, beforeEach } from 'node:test';
import assert from 'node:assert';
import { setupBackground } from '../../src/background.js';

describe('Background Service Worker', () => {
  beforeEach(() => {
    // Mock chrome API
    globalThis.chrome = {
      action: {
        onClicked: {
          addListener: mock.fn(),
        },
      },
      windows: {
        create: mock.fn(),
      },
    };
  });

  it('should register a listener for chrome.action.onClicked', () => {
    setupBackground();
    assert.strictEqual(chrome.action.onClicked.addListener.mock.callCount(), 1);
  });

  it('should call chrome.windows.create when clicked', () => {
    setupBackground();

    // Get the listener function that was passed to addListener
    const listener = chrome.action.onClicked.addListener.mock.calls[0].arguments[0];

    // Trigger the listener
    listener({ id: 123 });

    assert.strictEqual(chrome.windows.create.mock.callCount(), 1);
    const args = chrome.windows.create.mock.calls[0].arguments[0];
    assert.strictEqual(args.url, 'https://chat.openai.com');
    assert.strictEqual(args.type, 'popup');
    assert.strictEqual(args.width, 400);
    assert.strictEqual(args.height, 600);
  });
});
