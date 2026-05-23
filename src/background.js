const DEFAULT_CHATGPT_URL = 'https://chatgpt.com/';
const LAST_URL_STORAGE_KEY = 'lastChatGptUrl';
const CHAT_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function normalizeRestorableChatGptUrl(url) {
  try {
    const parsed = new URL(url);

    if (parsed.protocol !== 'https:' || parsed.hostname !== 'chatgpt.com') {
      return null;
    }

    const pathname = parsed.pathname.replace(/\/+$/, '') || '/';

    if (pathname === '/') {
      return DEFAULT_CHATGPT_URL;
    }

    const parts = pathname.split('/').filter(Boolean);

    if (parts.length === 2 && parts[0] === 'c' && CHAT_ID_PATTERN.test(parts[1])) {
      return `https://chatgpt.com/c/${parts[1]}`;
    }

    if (parts.length === 1 && CHAT_ID_PATTERN.test(parts[0])) {
      return `https://chatgpt.com/${parts[0]}`;
    }

    return null;
  } catch {
    return null;
  }
}

async function repairStoredChatGptUrl() {
  const stored = await chrome.storage.local.get(LAST_URL_STORAGE_KEY);
  const url = stored[LAST_URL_STORAGE_KEY];
  const normalizedUrl = normalizeRestorableChatGptUrl(url);

  if (normalizedUrl) {
    if (normalizedUrl !== url) {
      await chrome.storage.local.set({ [LAST_URL_STORAGE_KEY]: normalizedUrl });
    }

    return normalizedUrl;
  }

  await chrome.storage.local.set({ [LAST_URL_STORAGE_KEY]: DEFAULT_CHATGPT_URL });
  return DEFAULT_CHATGPT_URL;
}

async function getStoredChatGptUrl() {
  return repairStoredChatGptUrl();
}

async function setStoredChatGptUrl(url) {
  const normalizedUrl = normalizeRestorableChatGptUrl(url);

  if (!normalizedUrl) {
    const storedUrl = await repairStoredChatGptUrl();
    return { ok: false, url: storedUrl };
  }

  await chrome.storage.local.set({ [LAST_URL_STORAGE_KEY]: normalizedUrl });
  return { ok: true, url: normalizedUrl };
}

chrome.runtime.onInstalled.addListener(() => {
  repairStoredChatGptUrl();
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
