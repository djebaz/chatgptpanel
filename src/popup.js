// Send a message to the ChatGPT API
export function sendMessage(message, apiKey) {
  const chatContainer = document.getElementById('chat-container');
  const chatLog = document.getElementById('chat-log');

  // Make a request to the ChatGPT API
  return fetch('https://api.openai.com/v1/engine/davinci-codex/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + apiKey,
    },
    body: JSON.stringify({
      prompt: message,
      max_tokens: 50,
      n: 1,
      stop: '\n',
      temperature: 0.5,
    }),
  })
    .then(response => response.json())
    .then(data => {
      // Get the response from the ChatGPT API and add it to the chat log
      const response = data.choices[0].text.trim();
      const chatItem = document.createElement('div');
      chatItem.textContent = response;
      chatLog.appendChild(chatItem);
      chatContainer.scrollTop = chatContainer.scrollHeight;
    })
    .catch(error => {
      console.error('Error:', error);
      throw error;
    });
}

// Handle form submission
export function handleFormSubmit(event) {
  event.preventDefault();
  const chatContainer = document.getElementById('chat-container');
  const chatLog = document.getElementById('chat-log');
  const chatInput = document.getElementById('chat-input');
  const message = chatInput.value.trim();

  if (message) {
    const chatItem = document.createElement('div');
    chatItem.classList.add('chat-item', 'user');
    chatItem.textContent = message;
    chatLog.appendChild(chatItem);
    chatContainer.scrollTop = chatContainer.scrollHeight;

    // Get the user's OpenAI API key from the server
    return gapi.auth2
      .getAuthInstance()
      .signIn()
      .then(function () {
        const token = gapi.auth2.getAuthInstance().currentUser.get().getAuthResponse().id_token;
        return fetch('https://YOUR_SERVER_URL/getApiKey', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            token: token,
          }),
        });
      })
      .then(response => response.json())
      .then(data => {
        const apiKey = data.apiKey;
        return sendMessage(message, apiKey);
      })
      .catch(error => {
        console.error('Error:', error);
      });
  }
}

// Initialize the popup
export function initPopup() {
  // Load the Google Sign-In API
  if (typeof gapi !== 'undefined') {
    gapi.load('auth2', function () {
      gapi.auth2.init({
        client_id: 'YOUR_CLIENT_ID',
        scope: 'email',
      });
    });
  }

  const chatForm = document.getElementById('chat-form');
  if (chatForm) {
    chatForm.addEventListener('submit', handleFormSubmit);
  }
}

// Only run if we are in a browser environment
if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initPopup);
  } else {
    initPopup();
  }
}
