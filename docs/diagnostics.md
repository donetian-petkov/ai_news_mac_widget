# Diagnostics And Visual Verification

This project has a repeatable evidence pack for debugging app, backend, AI queue, feed, and widget problems without guessing.

## First Command For Any Bug

Run this before changing code:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget
npm run diagnose:quick
```

It writes a timestamped folder under `diagnostics/` and prints the report path. Open `REPORT.md` first.

## Visual/UI Bugs

For widget layout, window size, stale UI, missing icons, mode switching, or “what is on screen” problems, run:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget
npm run diagnose:visual
```

This adds:

- `visual/desktop.png`
- `visual/window-bounds.txt`

macOS may require Screen Recording and Accessibility permissions for the terminal or Codex app. If the window-bounds assertion fails, grant Accessibility permission and rerun.

## Full Verification

Before declaring a larger fix done:

```bash
cd /Users/donetianpetkov/ai_news/ai_news_mac_widget
npm run diagnose:full
npm run install:app
open "/Applications/AI News Widget.app"
```

`diagnose:full` also runs backend and native builds.

## Evidence Pack Contents

Each diagnostic folder contains:

- `REPORT.md` - human-readable summary, assertions, failed checks, and first files to inspect.
- `manifest.json` - machine-readable status for other AI agents.
- `logs/git-status.log` - dirty files and local state.
- `logs/git-recent-commits.log` - recent commits.
- `logs/backend-log-tail.log` - backend crashes, feed fetch failures, API failures, and AI queue logs.
- `logs/widget-debug-log-tail.log` - native app/widget debug events.
- `logs/runtime-json.log` - backend discovery file copied from `/tmp/ai-news-mac-widget-runtime.json`.
- `environment.json` - installed app paths, local app data files, runtime URL, and whether the runtime backend PID is alive.
- `api/*health*.json` - backend health probes.
- `api/*ai-jobs*.json` - queue size, in-flight jobs, dead letters, skips, drops, and stalled status.
- `api/*summary-debug*.json` - summary timing, empty results, errors, provider/model state.
- `api/*runtime-config*.json` - current runtime config when accessible.
- `visual/desktop.png` - optional screenshot of the current desktop.
- `visual/window-bounds.txt` - optional native window positions and sizes.

## Rules For Future AI Debugging

Before making a fix, inspect:

1. The latest `REPORT.md`.
2. `api/*ai-jobs*.json` for queue and stall evidence.
3. `logs/backend-log-tail.log` for backend or fetch failures.
4. `logs/widget-debug-log-tail.log` for native widget state problems.
5. `visual/desktop.png` and `visual/window-bounds.txt` for UI/layout issues.
6. `environment.json` when health probes fail, to see whether the runtime file is stale or the backend PID is dead.

Do not infer a root cause from screenshots alone when a diagnostic pack is available.

## Useful Modes

```bash
npm run diagnose:quick
npm run diagnose:visual
npm run diagnose:full
node scripts/diagnose.mjs --full --build --install --open
```

The last command builds, installs, opens, and captures a full pack in one run.
