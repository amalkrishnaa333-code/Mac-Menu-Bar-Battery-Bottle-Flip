#!/bin/bash
set -e

APP="BottleFlip"
BUNDLE="$APP.app"

echo "→ Compiling..."
swiftc \
    -framework AppKit \
    -framework IOKit \
    -framework Foundation \
    -O \
    Sources/main.swift \
    Sources/AppDelegate.swift \
    Sources/BatteryMonitor.swift \
    Sources/BottleView.swift \
    -o "$APP"

echo "→ Bundling..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$APP" "$BUNDLE/Contents/MacOS/"
cp Info.plist "$BUNDLE/Contents/"
rm "$APP"

# Copy bottle image asset
if [ -f ~/Desktop/bottle.png ]; then
    cp ~/Desktop/bottle.png "$BUNDLE/Contents/Resources/bottle.png"
else
    echo "WARNING: ~/Desktop/bottle.png not found — bottle image will be missing"
fi

echo "✓ Built $BUNDLE"
echo ""
echo "Run:   open $BUNDLE"
echo "Kill:  pkill BottleFlip"
