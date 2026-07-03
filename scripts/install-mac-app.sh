#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/native"
APP_NAME="AI News Widget"
APP_BUNDLE_NAME="$APP_NAME.app"
PROJECT_PATH="$NATIVE_DIR/AINewsMacWidget.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"
SOURCE_APP="$DERIVED_DATA_DIR/Build/Products/Release/AINewsMacApp.app"
INSTALL_DIR="/Applications/$APP_BUNDLE_NAME"
if [[ ! -w "/Applications" ]]; then
  INSTALL_DIR="${HOME}/Applications/$APP_BUNDLE_NAME"
fi
RESOURCES_DIR="$INSTALL_DIR/Contents/Resources"
WIDGET_APPEX="$INSTALL_DIR/Contents/PlugIns/AINewsWidgets.appex"
LOG_DIR="${HOME}/Library/Logs/AINewsMacWidget"
RUNTIME_INFO_PATH="/tmp/ai-news-mac-widget-runtime.json"
NODE_PATH="$(command -v node || true)"
NPM_PATH="$(command -v npm || true)"

mkdir -p "$LOG_DIR"
ruby "$ROOT_DIR/scripts/generate-xcodeproj.rb"
rm -rf "$DERIVED_DATA_DIR"

/usr/bin/osascript -e 'tell application "AI News Widget" to quit' >/dev/null 2>&1 || true
sleep 1

/usr/bin/xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme AINewsMacApp \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

mkdir -p "${HOME}/Applications"
rm -rf "$INSTALL_DIR"
cp -R "$SOURCE_APP" "$INSTALL_DIR"
mkdir -p "$RESOURCES_DIR"

cat > "$RESOURCES_DIR/backend-launch.json" <<JSON
{
  "repoRoot": "$ROOT_DIR",
  "runtimeInfoPath": "$RUNTIME_INFO_PATH",
  "logFile": "$LOG_DIR/backend.log",
  "nodePath": "$NODE_PATH",
  "npmPath": "$NPM_PATH"
}
JSON

if [[ -d "$WIDGET_APPEX" ]]; then
  /usr/bin/codesign --force --sign - --entitlements "$NATIVE_DIR/Support/AINewsWidgets.entitlements" "$WIDGET_APPEX"
fi
/usr/bin/codesign --force --deep --sign - --entitlements "$NATIVE_DIR/Support/AINewsMacApp.entitlements" "$INSTALL_DIR"

touch "$INSTALL_DIR"

echo "Installed $APP_NAME to $INSTALL_DIR"
echo "Launch it with: open \"$INSTALL_DIR\""
