chrome.action.onClicked.addListener((tab) => {
    chrome.windows.create({
      url: 'https://chat.openai.com',
      type: 'popup',
      width: 400,
      height: 600,
    });
  });
  