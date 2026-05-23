const DEFAULT_CHATGPT_URL = 'https://chatgpt.com/';
const LAST_URL_STORAGE_KEY = 'lastChatGptUrl';
const SIDE_PANEL_PENDING_URL_KEY = 'sidePanelPendingUrl';
const CHAT_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const iframe = document.getElementById('chatgpt-frame');

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

function fallbackCopyText(text) {
  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  textarea.style.pointerEvents = 'none';
  document.body.appendChild(textarea);
  textarea.select();
  textarea.setSelectionRange(0, textarea.value.length);

  let copied = false;

  try {
    copied = document.execCommand('copy');
  } catch {
    copied = false;
  }

  textarea.remove();
  return copied;
}

async function writeTextToClipboard(text) {
  if (!text) {
    return;
  }

  if (fallbackCopyText(text)) {
    return;
  }

  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // Ignore clipboard fallback failures and leave native page behavior in place.
  }
}

async function resolveInitialUrl() {
  const stored = await chrome.storage.local.get([SIDE_PANEL_PENDING_URL_KEY, LAST_URL_STORAGE_KEY]);
  const pendingUrl = normalizeRestorableChatGptUrl(stored[SIDE_PANEL_PENDING_URL_KEY]);
  const lastUrl = normalizeRestorableChatGptUrl(stored[LAST_URL_STORAGE_KEY]);
  const url = pendingUrl || lastUrl || DEFAULT_CHATGPT_URL;

  if (stored[SIDE_PANEL_PENDING_URL_KEY]) {
    await chrome.storage.local.remove(SIDE_PANEL_PENDING_URL_KEY);
  }

  if (url !== stored[LAST_URL_STORAGE_KEY]) {
    await chrome.storage.local.set({ [LAST_URL_STORAGE_KEY]: url });
  }

  return url;
}

window.addEventListener('message', event => {
  if (event.origin !== 'https://chatgpt.com' && !event.origin.endsWith('.chatgpt.com')) {
    return;
  }

  const { data } = event;

  if (data?.source !== 'chatgptpanel-copy-fallback' || typeof data.text !== 'string') {
    return;
  }

  void writeTextToClipboard(data.text);
});

void resolveInitialUrl().then(url => {
  iframe.src = url;
});
