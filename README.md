# chatgptpanel

Access OpenAI ChatGPT in a mini window, perfect for multitasking devs to stay connected without leaving their workspace.

This extension provides a dedicated action popup allowing you to open the official ChatGPT website in three ways:
- **Side Panel**: Pin ChatGPT to the side of your browser.
- **PopUp**: A clean, distraction-free popup window.
- **New Tab**: Standard full-tab experience.

## Development

### Prerequisites
- Node.js (v24+)
- PowerShell 7+

### Setup
```powershell
npm install
```

### Testing
We use the native Node.js test runner for manifest validation and Playwright for E2E verification.

```powershell
# Run all tests (Unit + E2E)
npm test

# Run manifest validation only
npm run test:unit
```

### Formatting
```powershell
npm run format:all
```
