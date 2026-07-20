#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

PROJECT_ROOT="${0:A:h:h}"
VERSION="${1:-0.1.0}"
APP_NAME="Codex Quota Ring"
PACKAGE_ID="dev.quota-ring.codex.pkg"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-ring-pkg.XXXXXX")"
PAYLOAD_ROOT="$WORK_ROOT/payload"
SCRIPTS_ROOT="$WORK_ROOT/scripts"
APP_DIR="$PAYLOAD_ROOT/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
OUTPUT_DIR="$PROJECT_ROOT/dist"

trap 'rm -rf "$WORK_ROOT"' EXIT
cd "$PROJECT_ROOT"

CACHE_ROOT="$WORK_ROOT/build-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

swift build -c release --cache-path "$CACHE_ROOT/swiftpm-cache"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$PAYLOAD_ROOT/Library/LaunchAgents" "$SCRIPTS_ROOT" "$OUTPUT_DIR"
cp ".build/release/CodexQuotaRing" "$CONTENTS/MacOS/CodexQuotaRing"
cp "$PROJECT_ROOT/resources/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_ROOT/resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
sed "s|__APP_BINARY__|/Applications/$APP_NAME.app/Contents/MacOS/CodexQuotaRing|g" \
  "$PROJECT_ROOT/resources/dev.quota-ring.codex.plist" \
  > "$PAYLOAD_ROOT/Library/LaunchAgents/dev.quota-ring.codex.plist"
cp "$PROJECT_ROOT/scripts/package-postinstall" "$SCRIPTS_ROOT/postinstall"
chmod 755 "$SCRIPTS_ROOT/postinstall"
codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$PAYLOAD_ROOT"

pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --scripts "$SCRIPTS_ROOT" \
  --identifier "$PACKAGE_ID" \
  --version "$VERSION" \
  --install-location / \
  "$OUTPUT_DIR/Codex-Quota-Ring-$VERSION.pkg"

echo "Created $OUTPUT_DIR/Codex-Quota-Ring-$VERSION.pkg"
