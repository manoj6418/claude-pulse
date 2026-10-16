#!/bin/sh
# Builds ClaudePulse.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
APP=build/ClaudePulse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudePulse "$APP/Contents/MacOS/ClaudePulse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    DEST="$HOME/Applications/ClaudePulse.app"
    mkdir -p "$HOME/Applications"
    pkill -x ClaudePulse 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed and launched $DEST"
fi
