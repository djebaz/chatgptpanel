const DEFAULT_CHATGPT_URL = 'https://chatgpt.com/';
const LAST_URL_STORAGE_KEY = 'lastChatGptUrl';
const ALLOWED_HOST_SUFFIXES = ['chatgpt.com'];

function isAllowedChatGptUrl(url) {
  try {
    const parsed = new URL(url);

    if (parsed.protocol !== 'https:') {
      return false;
    }

    return ALLOWED_HOST_SUFFIXES.some(suffix => parsed.hostname === suffix || parsed.hostname.endsWith(`.${suffix}`));
  } catch {
    return false;
  }
}

async function getStoredChatGptUrl() {
  const stored = await chrome.storage.local.get(LAST_URL_STORAGE_KEY);
  const url = stored[LAST_URL_STORAGE_KEY];

  return isAllowedChatGptUrl(url) ? url : DEFAULT_CHATGPT_URL;
}

async function setStoredChatGptUrl(url) {
  if (!isAllowedChatGptUrl(url)) {
    return { ok: false };
  }

  await chrome.storage.local.set({ [LAST_URL_STORAGE_KEY]: url });
  return { ok: true };
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.get(LAST_URL_STORAGE_KEY).then(stored => {
    if (!isAllowedChatGptUrl(stored[LAST_URL_STORAGE_KEY])) {
      return chrome.storage.local.set({ [LAST_URL_STORAGE_KEY]: DEFAULT_CHATGPT_URL });
    }

    return undefined;
  });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || typeof message !== 'object') {
    return false;
  }

  if (message.type === 'chatgpt-url-changed') {
    setStoredChatGptUrl(message.url).then(sendResponse);
    return true;
  }

  if (message.type === 'get-launch-url') {
    getStoredChatGptUrl().then(url => sendResponse({ url }));
    return true;
  }

  return false;
});
