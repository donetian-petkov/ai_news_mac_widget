# AI News Mac Widget

Standalone macOS AI News product derived from `ai_news_deploy_ready`.

It ships as an installed macOS app that supervises its own local Node/Prisma backend, plus native floating widgets for individual feeds, merged feeds, and the filtered feed.

## Structure

- `backend/` - local Node/Prisma API, RSS ingestion, AI jobs, filtered-feed matching, saved views, and widget endpoints.
- `native/` - SwiftUI companion app, floating widget windows, shared API client, theme system, and WidgetKit source.
- `scripts/` - app install/open helpers, backend build helpers, icon generation, and diagnostics.
- `docs/` - implementation notes and follow-up design docs.

## Main Features

- Local account login and local provider-key storage.
- Default feeds imported from the AI News project.
- Per-feed controls from the main page: turn feed fetching off/on and pause/resume AI.
- Filtered Feed as its own first-class feed driven by keyword rules.
- Fast keyword matching for filtered stories before slower semantic work finishes.
- AI actions for summaries, research, translations, neutral title rewrites, model/provider settings, usage totals, and budget/pending counts.
- Optional neutral-title filter for English and Bulgarian headlines, with global, per-feed, and per-category controls plus an on-demand story action.
- Story cards with images, summaries, research state, translation state, share action, save/pin actions, and source links.
- Sidebar health indicators showing loaded, pending, budget-blocked, hidden, and active feed state.
- Native floating widgets with:
  - individual feed widgets
  - filtered feed widget
  - merged feed widgets
  - column view
  - stack view
  - solid and transparent background modes
  - always-on-top behavior
  - per-widget size and position persistence
  - share button on each story
  - NEW label for unseen stack stories
  - stack navigation and stack load-more controls
- Drag-over merging for feed widgets, with title-chip unmerge.
- Saved Views page for saving, applying, editing, deleting, and rearranging widget layouts.
- Menu bar icon with quick app/widget actions.

## Install / Update

Run from the repo root:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget
npm install
npm run install:app
open "/Applications/AI News Widget.app"
```

The installed app starts and supervises its own backend. You normally do not need to run a backend command manually.

## Development Commands

```bash
npm run build:backend
npm run build:native
npm run install:app
npm run open:app
```

Useful backend-only commands:

```bash
npm run prisma:generate
npm run prisma:migrate
npm run start:backend
```

## Runtime Files And Logs

- Runtime backend URL: `/tmp/ai-news-mac-widget-runtime.json`
- Backend log: `~/Library/Logs/AINewsMacWidget/backend.log`
- App/widget debug log: `/tmp/ai-news-widget-debug.log`
- Local app data: `~/Library/Application Support/AINewsMacWidget/`

Health checks:

```bash
curl -s http://127.0.0.1:3000/api/health
curl -s http://127.0.0.1:3000/api/categories
```

## Operational Notes

- The app follows the backend runtime file when the backend port changes.
- If the app reports a backend/network error, check the runtime file and backend log first.
- Feed refresh now reloads the selected stories and resets the main list to the newest story instead of preserving a stale deep scroll offset.
- API request failures are logged with method, path, and URL so cancellation/timeout/connectivity errors are diagnosable.
- Hidden categories are presentation-level visibility; use feed controls to stop fetching or pause AI.
- Images are supported in the companion app and floating widgets when enabled.
