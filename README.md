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
It also generates local auth/encryption secrets on first run for the standalone app account system.
It tries Prisma migrations first and falls back to a local `db push` bootstrap if the SQLite state is brand new or messy.
If port `4000` is already in use, the backend will automatically move to the next available port and print the final URL.
The backend also writes its active local URL to a runtime file in your macOS temp directory so the Swift app can follow port changes automatically.

Native:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget/native
swift build
swift run AINewsMacApp
```

### Install / update the app (recommended)

Run these from the repo root, in order:

```bash
# 1. Fully stop the app AND its backend
#    (the installer quits the app but NOT the node backend, so a stale
#    old-code backend can survive and the new app will reuse it)
killall AINewsMacApp 2>/dev/null; pkill -f "dist/server.js" 2>/dev/null; rm -f /tmp/ai-news-mac-widget-runtime.json

# 2. Build + install (regenerates the Xcode project, builds the backend,
#    builds the app, copies it to /Applications, and codesigns it)
./scripts/install-mac-app.sh

# 3. Launch
open "/Applications/AI News Widget.app"
```

`install-mac-app.sh` does the full build for you — you do not run `xcodebuild` or the project generator yourself.

**Gotchas:**

- **Step 1 is not optional.** The installer stops the *app* but leaves the old *node backend* running. If you skip it, the freshly built app connects to the stale old-code backend and looks "still old."
- **Fully quit the app (⌘Q) before reinstalling.** A lingering window keeps showing the old build even after a successful install.
- **Do not run `npm run start` (the dev stack) at the same time as the installed app.** It spawns its own backend on port `4000` with possibly-old code and causes port confusion. Use *either* the installed app *or* the dev stack, not both.

The app auto-launches its own backend on start, so once installed you normally just `open` it — no separate backend command needed.

## Notes

- Images are intentionally disabled in the native app and widget layouts.
- The widget source layer is present, but packaging it as a signed `.app` plus WidgetKit extension still requires opening the repo in Xcode and wiring bundle/signing settings.
