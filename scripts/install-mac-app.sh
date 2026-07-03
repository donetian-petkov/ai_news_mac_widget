#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/native"
APP_NAME="AI News Widget"
APP_BUNDLE_NAME="$APP_NAME.app"
(
  cd "$NATIVE_DIR"
  swift build -c release --product AINewsMacApp >/dev/null
)
RELEASE_BIN_DIR="$(cd "$NATIVE_DIR" && swift build -c release --show-bin-path)"
SOURCE_BIN="$RELEASE_BIN_DIR/AINewsMacApp"
STAGING_DIR="$ROOT_DIR/.dist/$APP_BUNDLE_NAME"
INSTALL_DIR="${HOME}/Applications/$APP_BUNDLE_NAME"
MACOS_DIR="$STAGING_DIR/Contents/MacOS"
RESOURCES_DIR="$STAGING_DIR/Contents/Resources"
LOG_DIR="${HOME}/Library/Logs/AINewsMacWidget"
RUNTIME_INFO_PATH="/tmp/ai-news-mac-widget-runtime.json"

mkdir -p "$LOG_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$STAGING_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>AINewsMacApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.donetianpetkov.ai-news-mac-widget</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.news</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

cat > "$RESOURCES_DIR/backend-launch.json" <<JSON
{
  "repoRoot": "$ROOT_DIR",
  "runtimeInfoPath": "$RUNTIME_INFO_PATH",
  "logFile": "$LOG_DIR/backend.log"
}
JSON

cp "$SOURCE_BIN" "$MACOS_DIR/AINewsMacApp.bin"
chmod +x "$MACOS_DIR/AINewsMacApp.bin"

cat > "$MACOS_DIR/AINewsMacApp" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SELF_DIR/.." && pwd)"
RESOURCES_DIR="$APP_DIR/Resources"
CONFIG_PATH="$RESOURCES_DIR/backend-launch.json"
BACKEND_LOG="${HOME}/Library/Logs/AINewsMacWidget/backend.log"
RUNTIME_INFO_PATH="/tmp/ai-news-mac-widget-runtime.json"
REPO_ROOT=""

if [[ -f "$CONFIG_PATH" ]]; then
  REPO_ROOT="$(sed -n 's/.*"repoRoot"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$CONFIG_PATH")"
  RUNTIME_INFO_PATH="$(sed -n 's/.*"runtimeInfoPath"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$CONFIG_PATH" || true)"
  BACKEND_LOG="$(sed -n 's/.*"logFile"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$CONFIG_PATH" || true)"
fi

mkdir -p "$(dirname "$BACKEND_LOG")"

BACKEND_URL=""
if [[ -f "$RUNTIME_INFO_PATH" ]]; then
  BACKEND_URL="$(sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\(http[^"]*\)".*/\1/p' "$RUNTIME_INFO_PATH" | head -n 1)"
fi
if [[ -z "$BACKEND_URL" ]]; then
  BACKEND_URL="http://127.0.0.1:4000"
fi

if ! /usr/bin/curl -fsS "$BACKEND_URL/api/health" >/dev/null 2>&1; then
  if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
    nohup /bin/bash -lc "cd \"$REPO_ROOT\" && npm run start:backend" >>"$BACKEND_LOG" 2>&1 &
  fi
fi

exec "$SELF_DIR/AINewsMacApp.bin"
LAUNCHER
chmod +x "$MACOS_DIR/AINewsMacApp"

mkdir -p "${HOME}/Applications"
rm -rf "$INSTALL_DIR"
cp -R "$STAGING_DIR" "$INSTALL_DIR"

echo "Installed $APP_NAME to $INSTALL_DIR"
echo "Launch it with: open \"$INSTALL_DIR\""
