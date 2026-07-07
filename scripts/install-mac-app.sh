#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/native"
APP_NAME="AI News Widget"
APP_BUNDLE_NAME="$APP_NAME.app"
PROJECT_PATH="$NATIVE_DIR/AINewsMacWidget.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"
SOURCE_APP="$DERIVED_DATA_DIR/Build/Products/Release/AINewsMacApp.app"
SYSTEM_INSTALL_DIR="/Applications/$APP_BUNDLE_NAME"
USER_INSTALL_DIR="${HOME}/Applications/$APP_BUNDLE_NAME"
INSTALL_DIR="$SYSTEM_INSTALL_DIR"
STALE_INSTALL_DIR="$USER_INSTALL_DIR"
if [[ ! -w "/Applications" ]]; then
  INSTALL_DIR="$USER_INSTALL_DIR"
  STALE_INSTALL_DIR="$SYSTEM_INSTALL_DIR"
fi
RESOURCES_DIR="$INSTALL_DIR/Contents/Resources"
WIDGET_APPEX="$INSTALL_DIR/Contents/PlugIns/AINewsWidgets.appex"
LOG_DIR="${HOME}/Library/Logs/AINewsMacWidget"
RUNTIME_INFO_PATH="/tmp/ai-news-mac-widget-runtime.json"
NODE_PATH="$(command -v node || true)"
NPM_PATH="$(command -v npm || true)"
API_ENTRY_PATH="$ROOT_DIR/backend/apps/api/dist/server.js"
DATABASE_URL="file:$ROOT_DIR/backend/apps/api/prisma/dev.db"

mkdir -p "$LOG_DIR"
ruby "$ROOT_DIR/scripts/generate-xcodeproj.rb"
rm -rf "$DERIVED_DATA_DIR"

/usr/bin/osascript -e 'tell application "AI News Widget" to quit' >/dev/null 2>&1 || true
/usr/bin/killall AINewsMacApp >/dev/null 2>&1 || true
/usr/bin/killall AINewsWidgets >/dev/null 2>&1 || true
# Kill any backend this project started so the new build never reuses a stale
# old-code backend (the app adopts any healthy backend it finds), and clear the
# discovery file so the fresh app starts its own backend.
/usr/bin/pkill -f "$ROOT_DIR/backend/apps/api/dist/server.js" >/dev/null 2>&1 || true
/bin/rm -f "$RUNTIME_INFO_PATH" >/dev/null 2>&1 || true
sleep 1

"$NODE_PATH" "$ROOT_DIR/scripts/ensure-local-secrets.mjs"
DATABASE_URL="$DATABASE_URL" "$NODE_PATH" "$ROOT_DIR/scripts/ensure-local-db.mjs"
"$NPM_PATH" run build:backend

/usr/bin/xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme AINewsMacApp \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

mkdir -p "${HOME}/Applications"
HAD_STALE_COPY=0
if [[ -d "$STALE_INSTALL_DIR" ]]; then
  HAD_STALE_COPY=1
fi
rm -rf "$STALE_INSTALL_DIR"
rm -rf "$INSTALL_DIR"
cp -R "$SOURCE_APP" "$INSTALL_DIR"
mkdir -p "$RESOURCES_DIR"

cat > "$RESOURCES_DIR/backend-launch.json" <<JSON
{
  "repoRoot": "$ROOT_DIR",
  "runtimeInfoPath": "$RUNTIME_INFO_PATH",
  "logFile": "$LOG_DIR/backend.log",
  "nodePath": "$NODE_PATH",
  "npmPath": "$NPM_PATH",
  "apiEntryPath": "$API_ENTRY_PATH",
  "databaseUrl": "$DATABASE_URL"
}
JSON

if [[ -d "$WIDGET_APPEX" ]]; then
  /usr/bin/codesign --force --sign - --entitlements "$NATIVE_DIR/Support/AINewsWidgets.entitlements" "$WIDGET_APPEX"
fi
/usr/bin/codesign --force --deep --sign - --entitlements "$NATIVE_DIR/Support/AINewsMacApp.entitlements" "$INSTALL_DIR"

touch "$INSTALL_DIR"

echo "Installed $APP_NAME to $INSTALL_DIR"
if [[ "$HAD_STALE_COPY" -eq 1 ]]; then
  echo "Removed stale copy at $STALE_INSTALL_DIR"
fi
echo "Launch it with: open \"$INSTALL_DIR\""
