#!/bin/bash
set -e

echo "📦 Downloading Keyly..."
curl -fSL -o /tmp/Keyly.dmg https://github.com/hoaiphongdev/keyly/releases/latest/download/Keyly.dmg

if [ ! -s /tmp/Keyly.dmg ]; then
    echo "❌ Download failed. Check if the release exists."
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
hdiutil attach /tmp/Keyly.dmg -nobrowse -quiet -mountpoint /Volumes/Keyly

echo "📂 Copying app to /Applications..."
cp -r /Volumes/Keyly/Keyly.app /Applications/

echo "🔌 Unmounting..."
hdiutil detach /Volumes/Keyly -quiet

echo "🧹 Cleaning up..."
rm -f /tmp/Keyly.dmg

echo ""
echo "✅ Keyly installed successfully!"
echo ""
echo "⚠️  IMPORTANT: Grant Accessibility permission when prompted."
echo "   If shortcuts don't work, go to:"
echo "   System Settings → Privacy & Security → Accessibility"
echo "   Remove Keyly if listed, then re-add it."

