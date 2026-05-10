/**
 * ChatGPT Panel - Background Script
 * Opens ChatGPT in a standalone popup window when the extension icon is clicked.
 */

chrome.action.onClicked.addListener(() => {
  chrome.windows.create({
    url: 'https://chatgpt.com',
    type: 'popup',
    width: 480,
    height: 700
  });
});
