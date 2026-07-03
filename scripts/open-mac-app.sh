#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/AI News Widget.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$HOME/Applications/AI News Widget.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "AI News Widget.app is not installed."
  echo "Run: npm run install:app"
  exit 1
fi

/usr/bin/osascript -e 'tell application "AI News Widget" to quit' >/dev/null 2>&1 || true
sleep 1
open -n "$APP_PATH"
