#!/bin/bash

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-dmg>"
    exit 1
fi

DMG_PATH="$1"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
PRIVATE_KEY_FILE="sparkle_eddsa_private_key.txt"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ File not found: $DMG_PATH"
    exit 1
fi

if [ ! -d "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle not found. Run 'swift build' first."
    exit 1
fi

echo "🔏 Signing $DMG_PATH..."

if [ -f "$PRIVATE_KEY_FILE" ]; then
    SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH" -f "$PRIVATE_KEY_FILE")
else
    SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
fi

echo ""
echo "✅ Signature generated!"
echo ""
echo "Add this to your appcast.xml <enclosure> tag:"
echo "sparkle:edSignature=\"$SIGNATURE\""
echo ""
echo "Also update the length attribute with the file size:"
echo "length=\"$(stat -f%z "$DMG_PATH")\""

