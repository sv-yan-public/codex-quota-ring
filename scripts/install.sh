#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_NAME="Codex Quota Ring"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

cd "$PROJECT_ROOT"
CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-ring-build.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT"' EXIT
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
swift package clean --cache-path "$CACHE_ROOT/swiftpm-cache"
swift build -c release --cache-path "$CACHE_ROOT/swiftpm-cache"

launchctl bootout "gui/$UID/dev.quota-ring.codex" 2>/dev/null || true
pkill -x CodexQuotaRing 2>/dev/null || true
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/CodexQuotaRing" "$CONTENTS/MacOS/CodexQuotaRing"
cp "$PROJECT_ROOT/resources/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_ROOT/resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__APP_BINARY__|$CONTENTS/MacOS/CodexQuotaRing|g" \
  "$PROJECT_ROOT/resources/dev.quota-ring.codex.plist" \
  > "$HOME/Library/LaunchAgents/dev.quota-ring.codex.plist"

launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/dev.quota-ring.codex.plist"

echo "Installed $APP_DIR"
