#!/bin/bash
# Build appcast.xml for one release with Sparkle's generate_appcast.
# The appcast is uploaded next to Keyly.dmg as a release asset, and the app
# reads it from releases/latest/download/appcast.xml.
#
#   SPARKLE_PRIVATE_KEY  EdDSA private key (CI secret), or
#   SPARKLE_KEY_FILE     path to the exported private key file.
#   DOWNLOAD_URL_PREFIX  override the enclosure URL prefix (local testing).
set -euo pipefail

VERSION="${1:-}"
DMG_PATH="${2:-.build/Keyly.dmg}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
WORK_DIR=".build/appcast"
PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/hoaiphongdev/keyly/releases/download/keyly-$VERSION/}"

if [[ -z "$VERSION" || ! -f "$DMG_PATH" ]]; then
    echo "Usage: $0 <version> [path-to-Keyly.dmg]" >&2
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp "$DMG_PATH" "$WORK_DIR/Keyly.dmg"
./scripts/release-notes.sh "$VERSION" > "$WORK_DIR/Keyly.md"

ARGS=(--download-url-prefix "$PREFIX" --embed-release-notes --link "https://github.com/hoaiphongdev/keyly" -o "$WORK_DIR/appcast.xml")

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" --ed-key-file - "${ARGS[@]}" "$WORK_DIR"
elif [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    "$SPARKLE_BIN/generate_appcast" --ed-key-file "$SPARKLE_KEY_FILE" "${ARGS[@]}" "$WORK_DIR"
else
    echo "❌ Set SPARKLE_PRIVATE_KEY or SPARKLE_KEY_FILE" >&2
    exit 1
fi

grep -q "sparkle:edSignature" "$WORK_DIR/appcast.xml" || {
    echo "❌ appcast.xml has no EdDSA signature" >&2
    exit 1
}
grep -q "<sparkle:version>$VERSION</sparkle:version>" "$WORK_DIR/appcast.xml" || {
    echo "❌ appcast.xml does not contain version $VERSION (check the DMG's Info.plist)" >&2
    exit 1
}

echo "✅ $WORK_DIR/appcast.xml"
