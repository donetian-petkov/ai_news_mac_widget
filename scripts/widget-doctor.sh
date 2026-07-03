#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/AI News Widget.app"
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH="$HOME/Applications/AI News Widget.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "app: missing"
  echo "install: run npm run install:app"
  exit 1
fi

APPEX_PATH="$APP_PATH/Contents/PlugIns/AINewsWidgets.appex"
if [[ ! -d "$APPEX_PATH" ]]; then
  echo "app: $APP_PATH"
  echo "widget-extension: missing"
  exit 1
fi

REGISTERED="no"
if pluginkit -m -A -D | rg -q "com\\.donetianpetkov\\.ainewsmacwidget\\.widgets"; then
  REGISTERED="yes"
fi

echo "app: $APP_PATH"
echo "widget-extension: $APPEX_PATH"
echo "registered: $REGISTERED"

if [[ "$REGISTERED" != "yes" ]]; then
  echo "next: launch the app once with npm run open:app"
  exit 2
fi
