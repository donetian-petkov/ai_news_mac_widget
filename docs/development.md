# Development And Operations

Everything needed to build, run, and troubleshoot the app beyond the README quick start.

## Repository Structure

- `backend/` - local Node/Prisma API, RSS ingestion, AI jobs, filtered-feed matching, saved views, and widget endpoints.
- `native/` - SwiftUI management app, floating widget windows, shared API client, theme system, and WidgetKit source.
- `scripts/` - app install/open helpers, backend build helpers, icon generation, and diagnostics.
- `docs/` - implementation notes and follow-up design docs.

## Commands

```bash
npm run build:backend
npm run build:native
npm run install:app
npm run open:app
```

Backend-only commands:

```bash
npm run prisma:generate
npm run prisma:migrate
npm run start:backend
```

If you are locked out of your local account, reset the password from this Mac with `npm run password:reset`, or use Reset password on the app's sign-in screen.

## Runtime Files And Logs

- Runtime backend URL: `/tmp/ai-news-mac-widget-runtime.json`
- Backend log: `~/Library/Logs/AINewsMacWidget/backend.log`
- App/widget debug log: `/tmp/ai-news-widget-debug.log`
- Local app data: `~/Library/Application Support/AINewsMacWidget/`

Health checks (the backend usually listens on port 3000; check the runtime file if it moved):

```bash
curl -s http://127.0.0.1:3000/api/health
curl -s http://127.0.0.1:3000/api/categories
```

## Diagnostics

Before changing code for a reported bug, generate an evidence pack with `npm run diagnose:quick`. For widget layout, window size, mode switching, stale UI, or icon problems, use `npm run diagnose:visual`. See [diagnostics.md](diagnostics.md) for the full runbook.

## Operational Notes

- The installed app records which checkout it was installed from. If you install from a different copy of the repo, the app runs that copy's backend and database, so your account may appear missing. Reinstall from the checkout you use.
- The app follows the backend runtime file when the backend port changes.
- If the app reports a backend/network error, check the runtime file and backend log first.
- Feed refresh reloads the selected stories and resets the main list to the newest story instead of preserving a stale deep scroll offset.
- API request failures are logged with method, path, and URL so cancellation/timeout/connectivity errors are diagnosable.
