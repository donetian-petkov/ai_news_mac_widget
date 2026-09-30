# Windows Native Implementation Plan

This plan is for re-creating AI News macOS Floating Widgets as a native Windows 11 app with the same floating widgets. It is written so another developer or model can pick it up and implement directly.

## The Short Version

The backend can be reused almost as-is, because it is plain Node, Express, Prisma, and SQLite. The Mac app itself cannot be reused, because it is SwiftUI and AppKit. The Windows work is therefore a new desktop app that talks to the same backend API, plus a small set of backend changes so the backend stops assuming macOS file paths.

## Non-Negotiables

- A native Windows desktop app, not a browser tab or a web wrapper around the dashboard.
- Floating widgets are real top-level windows that stay on top, can be moved and resized, and remember their size and position.
- The installed app starts and supervises its own backend, exactly like the Mac app. The user never runs a backend command.
- Same story rules as the Mac widget: hidden stories disappear immediately, NEW labels clear once seen, power and fetch state are shown as text.
- Same local-only model: the account, provider keys, and database stay on the machine, and password reset only works from the machine itself.

## Recommended Stack

- **App:** C# with WinUI 3 on the Windows App SDK (.NET 8). It is Microsoft's current native UI stack, it supports transparent backgrounds (Mica/Acrylic), always-on-top windows, and custom title bars, and it is the only stack that can also feed the Windows 11 Widgets board.
- **Backend:** the existing `backend/` Node API, shipped with a bundled `node.exe` so the user does not need Node installed.
- **Installer:** MSIX package (clean install, update, and uninstall, and required for the Widgets board). Inno Setup is the fallback if MSIX signing gets in the way.

## What Maps To What

| macOS piece | Where it lives today | Windows equivalent |
| --- | --- | --- |
| Management app (SwiftUI) | `native/Sources/AINewsMacApp/RootView.swift` | WinUI 3 main window with a sidebar and story list |
| Floating widgets (`NSPanel`, always on top) | `native/Sources/AINewsMacApp/FloatingWidgetPanel.swift` | One WinUI 3 window per widget using `AppWindow` with `OverlappedPresenter.IsAlwaysOnTop`, no taskbar button, custom title bar |
| Transparent widget background | `Theme.swift` | Acrylic or Mica backdrop, with a solid-color fallback |
| Drag a widget onto another to merge | `FloatingWidgetPanel.swift` (overlap ratio check) | Same overlap check on `AppWindow.Changed` when a move ends |
| Menu bar icon | `AINewsMacApp.swift` | Notification-area (system tray) icon with a context menu, for example via `H.NotifyIcon.WinUI` |
| Backend supervisor | `BackendSupervisor.swift` | `System.Diagnostics.Process` running bundled `node.exe`, attached to a Job Object so the backend dies when the app dies |
| Backend discovery and runtime file | `BackendDiscovery.swift`, `/tmp/ai-news-mac-widget-runtime.json` | Same JSON file under `%LOCALAPPDATA%\AINewsWidget\runtime.json` |
| API client, models, app state | `native/Sources/AINewsWidgetShared/` | C# port: `HttpClient` client, records for models, an observable `AppState` class. The Swift files are the spec |
| Session and settings storage | `SessionStore.swift` (UserDefaults) | Token in Windows Credential Manager, settings in `%LOCALAPPDATA%\AINewsWidget\settings.json` |
| WidgetKit desktop widget | `native/Sources/AINewsWidgetExtension/` | Optional: Windows 11 Widgets board provider using Adaptive Cards (phase 5) |
| `ainewswidget://` URL scheme | `AINewsMacApp-Info.plist` | Protocol activation declared in the MSIX manifest |
| Logs and app data | `~/Library/Logs/...`, `~/Library/Application Support/...` | `%LOCALAPPDATA%\AINewsWidget\Logs` and `%LOCALAPPDATA%\AINewsWidget\Data` |

## Backend Changes Needed

These are small and should land first, because the Mac app benefits from them too.

- The runtime file defaults to `/tmp/ai-news-mac-widget-runtime.json` (`backend/apps/api/src/server.ts`). Default to `os.tmpdir()` instead, and let the app pass an explicit path through the existing `AI_NEWS_MAC_WIDGET_RUNTIME_FILE` variable.
- Add `"windows"` to the Prisma `binaryTargets` so the Windows query engine is bundled.
- Check `scripts/ensure-local-secrets.mjs`, `ensure-local-db.mjs`, and `reset-password.mjs` for Unix-only paths and shell calls.
- `scripts/diagnose.mjs` uses `screencapture`, `osascript`, and macOS paths. Give it a Windows branch that uses PowerShell for screenshots and window bounds.
- Keep the loopback-only rule on password reset. On Windows, confirm the backend binds to `127.0.0.1` only, so the firewall prompt never appears.

## Implementation Phases

1. **Backend on Windows.** Make the path changes above, then run the backend by hand on a Windows machine with `npm run start:backend` and pass the existing backend tests.
2. **Shell app and supervisor.** WinUI 3 app that starts bundled `node.exe`, waits for `/api/health`, reads the runtime file, and shows sign-in, register, and reset password. Tray icon with Open, Show widget, Power off, and Quit.
3. **Management app.** Sidebar with feeds and health, story list, feed controls, AI settings, Saved Views. Port models and API calls from the Swift shared module one file at a time.
4. **Floating widgets.** Column and stack views, always on top, size and position saved per widget, transparent mode, share and hide actions, NEW labels, stack navigation and load more, drag-to-merge and title-chip unmerge.
5. **Windows 11 Widgets board (optional).** A widget provider that shows the latest stories from the same snapshot data the Mac WidgetKit extension uses.
6. **Packaging.** MSIX with bundled Node and Prisma engine, start-on-login option, update path, and uninstall that leaves or removes user data by choice.

## Acceptance Criteria

- Fresh Windows 11 machine with no Node installed: install the package, open the app, register, and see stories within a couple of minutes.
- Closing the app stops the backend; reopening starts it again on a free port and the app finds it.
- A floating widget stays above other windows, keeps its size and position after a restart, and switches between column and stack view.
- Dragging one widget onto another merges them; clicking the title chip splits them again.
- Password reset works from the sign-in screen and shows a clear message when the username does not exist.
- The diagnostics command produces a report on Windows.

## Risks To Watch

- **Always-on-top and full-screen apps.** Windows can hide topmost windows behind full-screen games and video. Decide whether that is acceptable before building workarounds.
- **Transparency cost.** Acrylic on many small windows can use noticeable GPU. Keep the solid mode as the default.
- **Antivirus and SmartScreen.** An unsigned app that launches `node.exe` may be flagged. Budget for a code-signing certificate.
- **Port and firewall prompts.** Binding to anything other than `127.0.0.1` triggers a firewall dialog on first run.
- **Two code bases for one UI.** Every future widget change has to be made in Swift and in C#. Keep behavior rules in this plan and the Android plan in sync.
