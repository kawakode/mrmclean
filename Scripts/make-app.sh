#!/bin/bash
# Assemble dist/MrMcLean.app from a release build, ad-hoc sign it, and package a
# DMG and a zip. Usage: Scripts/make-app.sh <version> [build]
set -euo pipefail

VERSION="${1:-0.0.0}"
BUILD="${2:-$(date +%Y%m%d%H%M)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="dist/MrMcLean.app"
CONTENTS="$APP/Contents"

rm -rf dist
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Building release binary"
if swift build -c release --arch arm64 --arch x86_64; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    ARCH_NOTE="universal (arm64 + x86_64)"
else
    echo "    universal build failed, building for the host architecture only"
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
    ARCH_NOTE="$(uname -m) only"
fi

cp "$BIN_DIR/MrMcLean" "$CONTENTS/MacOS/MrMcLean"
chmod +x "$CONTENTS/MacOS/MrMcLean"

echo "==> Writing Info.plist ($VERSION / $BUILD)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    Resources/Info.plist.template > "$CONTENTS/Info.plist"

echo "==> Rendering icon"
if swift Scripts/make-icon.swift dist/AppIcon.iconset \
    && iconutil -c icns dist/AppIcon.iconset -o "$CONTENTS/Resources/AppIcon.icns"; then
    echo "    icon ok"
else
    echo "    icon step skipped"
fi
rm -rf dist/AppIcon.iconset

echo "==> Ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP" || true

echo "==> Packaging"
DMG="dist/MrMcLean-$VERSION.dmg"
ZIP="dist/MrMcLean-$VERSION.zip"
hdiutil create -quiet -volname "MrMcLean" -srcfolder "$APP" -ov -format UDZO "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Built $ARCH_NOTE"
ls -lh "$DMG" "$ZIP"
