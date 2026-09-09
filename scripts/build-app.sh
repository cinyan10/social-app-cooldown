#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="${ROOT}/.build/release"
APP_DIR="${ROOT}/.build/SocialCooldown.app"

cd "$ROOT"
CLANG_MODULE_CACHE_PATH="/tmp/social-cooldown-swift-cache" \
SWIFT_MODULECACHE_PATH="/tmp/social-cooldown-swift-cache" \
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/SocialCooldown" "$APP_DIR/Contents/MacOS/SocialCooldown"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing makes local launch-at-login registration work during development.
codesign --force --deep --sign - "$APP_DIR"
echo "Built $APP_DIR"
