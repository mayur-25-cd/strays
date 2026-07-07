#!/bin/bash
# Builds Strays and assembles a double-clickable .app bundle in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP_NAME="Strays"

echo "› Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "✗ Build product not found at $BIN_PATH" >&2
    exit 1
fi

APP_DIR="$ROOT/dist/$APP_NAME.app"
echo "› Assembling bundle → $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ROOT/dist/AppIcon.icns" ]]; then
    cp "$ROOT/dist/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so the local build launches without a spurious "damaged" prompt.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Built $APP_DIR"
echo "  Run with: open \"$APP_DIR\""
