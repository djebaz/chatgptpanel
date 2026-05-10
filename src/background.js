export function setupBackground() {
  chrome.action.onClicked.addListener(tab => {
    chrome.windows.create({
      url: 'https://chat.openai.com',
      type: 'popup',
      width: 400,
      height: 600,
    });
  });
}

// Only run if we are in a browser extension context
if (typeof chrome !== 'undefined' && chrome.action && chrome.action.onClicked) {
  setupBackground();
}
