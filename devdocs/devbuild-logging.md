# Dev build logging + packaging

Moved to `devdocs/features/devbuild-logging.md` for release tracking. Key points:

- Logging gate uses manifest `version_name`: prod suppresses non-error logs; dev (`-dev` suffix) prints them.
- Packager defaults to `scripts/package-config.json`, derives `AppName` from config or manifest name, and writes `version_name` only to staged manifest.
- Dev build command: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-extension.ps1 -DevBuild` → `<AppName>-<version>-dev` dist folder/zip with flat root.
