const DEFAULT_CHATGPT_URL = 'https://chatgpt.com/';

async function getLaunchUrl() {
  try {
    const response = await chrome.runtime.sendMessage({ type: 'get-launch-url' });
    return response?.url || DEFAULT_CHATGPT_URL;
  } catch {
    return DEFAULT_CHATGPT_URL;
  }
}

document.getElementById('btn-sidepanel').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

  if (tab) {
    const url = await getLaunchUrl();
    await chrome.storage.local.set({ sidePanelPendingUrl: url });
    await chrome.sidePanel.open({ windowId: tab.windowId });
  }

  window.close();
});

document.getElementById('btn-popup').addEventListener('click', async () => {
  const url = await getLaunchUrl();

  await chrome.windows.create({
    url,
    type: 'popup',
    width: 480,
    height: 700,
  });

  window.close();
});

document.getElementById('btn-tab').addEventListener('click', async () => {
  const url = await getLaunchUrl();
  await chrome.tabs.create({ url });
  window.close();
});
