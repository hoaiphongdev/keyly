#!/bin/bash
# Sign Keyly.app (and the embedded Sparkle parts) with one stable identity.
# Every nested Sparkle binary must carry the same identity as the app, otherwise
# Sparkle refuses to install updates. Hardened Runtime stays off: library
# validation would reject Sparkle because a self-signed cert has no Team ID.
#
#   KEYLY_SIGN_IDENTITY  SHA-1 hash (preferred) or name of the code signing identity.
#                        Unset → ad-hoc locally, hard failure in CI.
set -euo pipefail

APP_BUNDLE="${1:-}"
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
    echo "Usage: $0 <path-to-Keyly.app>" >&2
    exit 1
fi

IDENTITY="${KEYLY_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    if [[ "${CI:-}" == "true" ]]; then
        echo "❌ KEYLY_SIGN_IDENTITY is not set. Refusing to ship an ad-hoc build: users would lose Accessibility permission on update." >&2
        exit 1
    fi
    echo "   ⚠️ KEYLY_SIGN_IDENTITY not set, signing ad-hoc (local testing only)"
    IDENTITY="-"
fi

sign() {
    codesign --force --timestamp=none --sign "$IDENTITY" "$1"
}

SPARKLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
    # Keyly is not sandboxed, so Sparkle's XPC services are not needed.
    rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
    sign "$SPARKLE/Versions/B/Autoupdate"
    sign "$SPARKLE/Versions/B/Updater.app"
    sign "$SPARKLE"
fi

sign "$APP_BUNDLE"

codesign --verify --deep --strict "$APP_BUNDLE"
echo "   ✅ Signed with: $IDENTITY"
