const DEFAULT_CHATGPT_URL = 'https://chatgpt.com/';
const LAST_URL_STORAGE_KEY = 'lastChatGptUrl';
const SIDE_PANEL_PENDING_URL_KEY = 'sidePanelPendingUrl';
const iframe = document.getElementById('chatgpt-frame');

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
  const pendingUrl = stored[SIDE_PANEL_PENDING_URL_KEY];
  const lastUrl = stored[LAST_URL_STORAGE_KEY];
  const url = pendingUrl || lastUrl || DEFAULT_CHATGPT_URL;

  if (pendingUrl) {
    await chrome.storage.local.remove(SIDE_PANEL_PENDING_URL_KEY);
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
