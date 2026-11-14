#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UPDATE_SCREENSHOTS=0
for arg in "$@"; do
    case "$arg" in
        --update-screenshots)
            UPDATE_SCREENSHOTS=1
            ;;
        *)
            echo "Usage: Scripts/build-app.sh [--update-screenshots]" >&2
            exit 2
            ;;
    esac
done

APP_NAME="BusLensMac"
REL_BUNDLE="build/$APP_NAME.app"
ICONSET="build/AppIcon.iconset"

echo "==> Building $APP_NAME (release, arm64, macOS 14.0+)..."
swift build -c release --arch arm64

BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

echo "==> Assembling $REL_BUNDLE..."
rm -rf "$REL_BUNDLE" "$ICONSET"
mkdir -p "$REL_BUNDLE/Contents/MacOS" "$REL_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$REL_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$REL_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Scripts/Info.plist" "$REL_BUNDLE/Contents/Info.plist"

echo "==> Generating AppIcon.icns..."
swift "Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$REL_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Ad-hoc signing & verifying..."
codesign --force --deep --sign - "$REL_BUNDLE"
codesign --verify --deep --strict "$REL_BUNDLE"

if [[ "$UPDATE_SCREENSHOTS" -eq 1 ]]; then
    mkdir -p "docs"
    echo "==> Rendering 2x Retina screenshots (EN + zh-Hans) to docs/..."
    "$REL_BUNDLE/Contents/MacOS/$APP_NAME" --export-screenshots docs --lang en
    "$REL_BUNDLE/Contents/MacOS/$APP_NAME" --export-screenshots docs --lang zh
fi

echo "✓ Built $REL_BUNDLE"
