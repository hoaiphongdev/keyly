#!/bin/bash
set -e

APP_BUNDLE=".build/release/Keyly.app"
DMG_FILE=".build/Keyly.dmg"

echo "🔍 Verifying build artifacts..."

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ App bundle not found: $APP_BUNDLE"
    exit 1
fi
echo "   ✅ App bundle exists"

if [ ! -f "$DMG_FILE" ]; then
    echo "❌ DMG not found: $DMG_FILE"
    exit 1
fi
echo "   ✅ DMG exists"

if [ ! -f "$APP_BUNDLE/Contents/MacOS/Keyly" ]; then
    echo "❌ Executable not found in app bundle"
    exit 1
fi
echo "   ✅ Executable exists"

if [ ! -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    echo "❌ Info.plist not found"
    exit 1
fi
echo "   ✅ Info.plist exists"

echo "   🔍 Testing DMG mount..."
hdiutil attach "$DMG_FILE" -mountpoint /tmp/keyly_verify_mount -nobrowse -quiet 2>/dev/null || {
    echo "❌ Failed to mount DMG"
    exit 1
}

if [ ! -d "/tmp/keyly_verify_mount/Keyly.app" ]; then
    hdiutil detach /tmp/keyly_verify_mount -quiet
    echo "❌ Keyly.app not found in DMG"
    exit 1
fi

hdiutil detach /tmp/keyly_verify_mount -quiet
echo "   ✅ DMG mounts successfully"

APP_SIZE=$(du -sh "$APP_BUNDLE" | awk '{print $1}')
DMG_SIZE=$(du -sh "$DMG_FILE" | awk '{print $1}')
echo ""
echo "📊 Build sizes:"
echo "   App bundle: $APP_SIZE"
echo "   DMG file: $DMG_SIZE"

echo ""
echo "✅ All verifications passed!"
