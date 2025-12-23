#!/bin/bash
set -e

DMG_PATH="${1:-}"

if [ -n "$DMG_PATH" ]; then
    echo "📦 Using local DMG: $DMG_PATH"
    cp "$DMG_PATH" /tmp/Keyly.dmg
else
    echo "📦 Downloading Keyly..."
    curl -fSL -o /tmp/Keyly.dmg https://github.com/hoaiphongdev/keyly/releases/latest/download/Keyly.dmg
fi

if [ ! -s /tmp/Keyly.dmg ]; then
    echo "❌ DMG file not found or empty"
    exit 1
fi

if pgrep -x "Keyly" > /dev/null; then
    echo "🔄 Stopping existing Keyly..."
    pkill -x "Keyly" || true
    sleep 1
fi

if [ -d "/Applications/Keyly.app" ]; then
    echo "🗑️  Removing old version..."
    rm -rf /Applications/Keyly.app
fi

echo "🔐 Resetting accessibility permissions..."
tccutil reset Accessibility com.keyly.app 2>/dev/null || true

echo "💿 Mounting DMG..."
MOUNT_OUTPUT=$(hdiutil attach /tmp/Keyly.dmg -nobrowse)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/[^"]*' | head -1)

if [ -z "$MOUNT_POINT" ]; then
    echo "❌ Failed to mount DMG"
    exit 1
fi

echo "📂 Copying app to /Applications..."
cp -r "$MOUNT_POINT/Keyly.app" /Applications/

echo "🔓 Removing quarantine attribute..."
xattr -cr /Applications/Keyly.app

echo "🔌 Unmounting..."
hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true

echo "🧹 Cleaning up..."
rm -f /tmp/Keyly.dmg

echo ""
echo "✅ Keyly installed successfully!"
echo ""
echo "⚠️  IMPORTANT: Grant Accessibility permission."
echo "   If shortcuts don't work, go to:"
echo "   System Settings → Privacy & Security → Accessibility"
echo "   Remove Keyly if listed, then re-add it."

