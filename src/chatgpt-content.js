const COPY_BUTTON_PATTERN = /\bcopy\b/i;
const OBSERVED_STATE = {
  lastUrl: null,
};

function sendUrlUpdate(url) {
  if (!url || OBSERVED_STATE.lastUrl === url) {
    return;
  }

  OBSERVED_STATE.lastUrl = url;
  void chrome.runtime.sendMessage({ type: 'chatgpt-url-changed', url }).catch(() => undefined);
}

function notifyCurrentUrl() {
  sendUrlUpdate(window.location.href);
}

function scheduleUrlCheck() {
  queueMicrotask(notifyCurrentUrl);
}

function startUrlWatchers() {
  window.addEventListener('popstate', scheduleUrlCheck);
  window.addEventListener('hashchange', scheduleUrlCheck);

  new MutationObserver(scheduleUrlCheck).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
  });

  window.setInterval(notifyCurrentUrl, 1000);
}

function extractCopyText(button) {
  const codeBlock = button.closest('pre');

  if (codeBlock?.innerText?.trim()) {
    return codeBlock.innerText.trim();
  }

  const article = button.closest('article');

  if (article?.innerText?.trim()) {
    return article.innerText.trim();
  }

  const nearestBlock = button.closest('[data-message-author-role], [data-testid], main, section, div');
  return nearestBlock?.innerText?.trim() || '';
}

function findCopyButton(target) {
  if (!(target instanceof Element)) {
    return null;
  }

  return target.closest('button, [role="button"]');
}

function looksLikeCopyButton(button) {
  const label = [button.getAttribute('aria-label'), button.getAttribute('title'), button.textContent].filter(Boolean).join(' ');

  return COPY_BUTTON_PATTERN.test(label);
}

window.addEventListener(
  'click',
  event => {
    const button = findCopyButton(event.target);

    if (!button || !looksLikeCopyButton(button) || window.top === window.self) {
      return;
    }

    const text = extractCopyText(button);

    if (!text) {
      return;
    }

    window.parent.postMessage(
      {
        source: 'chatgptpanel-copy-fallback',
        text,
      },
      '*'
    );
  },
  true
);

notifyCurrentUrl();
startUrlWatchers();
