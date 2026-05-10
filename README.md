# chatgptpanel

Access OpenAI ChatGPT in a mini window, perfect for multitasking devs to stay connected without leaving their workspace.

This extension is a **Simple Wrapper** that opens the official ChatGPT website in a dedicated popup window, providing a distraction-free and easily accessible interface.

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
