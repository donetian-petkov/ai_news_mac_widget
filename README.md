# AI News Mac Widget

Standalone macOS widget project derived from `ai_news_deploy_ready`.

## Structure

- `backend/`
  - Node/Prisma local backend derived from the existing AI News feed and AI pipeline
- `native/`
  - Swift package containing the macOS companion app, shared models/client, and WidgetKit source layer
- `docs/`
  - implementation notes and follow-up docs

## Current Implementation

- Account auth and provider-key storage are reused from the AI News backend.
- Categories are backed by collection records and exposed through widget-specific REST routes.
- macOS companion app is implemented in SwiftUI with:
  - account sign-in
  - category list
  - 5/10 story expansion
  - reset/top controls
  - pinning
  - on-demand summary/research/translation buttons
- Widget source files are included in the Swift package so the widget data model, intents, and layouts stay aligned with the app.

## Run

Backend:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget
npm install
npm run prisma:generate
npm run start:backend
```

`npm run start:backend` initializes the local SQLite database first, then builds and launches the backend, so you do not need a separate manual build step for a clean clone.
It tries Prisma migrations first and falls back to a local `db push` bootstrap if the SQLite state is brand new or messy.
If port `4000` is already in use, the backend will automatically move to the next available port and print the final URL.
The backend also writes its active local URL to a runtime file in your macOS temp directory so the Swift app can follow port changes automatically.

Native:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget/native
swift build
swift run AINewsMacApp
```

Install like a normal Mac app:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget
npm run install:app
open "$HOME/Applications/AI News Widget.app"
```

## Notes

- Images are intentionally disabled in the native app and widget layouts.
- The widget source layer is present, but packaging it as a signed `.app` plus WidgetKit extension still requires opening the repo in Xcode and wiring bundle/signing settings.
