document.getElementById('btn-sidepanel').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
  if (tab) {
    await chrome.sidePanel.open({windowId: tab.windowId});
  }
  window.close();
});

document.getElementById('btn-popup').addEventListener('click', () => {
  chrome.windows.create({
    url: 'https://chatgpt.com',
    type: 'popup',
    width: 480,
    height: 700
  });
  window.close();
});

document.getElementById('btn-tab').addEventListener('click', () => {
  chrome.tabs.create({ url: 'https://chatgpt.com' });
  window.close();
});
