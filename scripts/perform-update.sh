#!/bin/bash
set -euo pipefail

DOWNLOAD_URL="${1:-}"
APP_PATH="${2:-}"

if [[ -z "$DOWNLOAD_URL" || -z "$APP_PATH" ]]; then
    echo "Usage: $0 <download_url> <app_path>" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
DMG_PATH="$TEMP_DIR/Keyly.dmg"
MOUNT_POINT="$TEMP_DIR/mount"

cleanup() {
    if [[ -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

curl -L --progress-bar --connect-timeout 30 --max-time 300 -o "$DMG_PATH" "$DOWNLOAD_URL" || {
    echo "Failed to download update" >&2
    exit 1
}

mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet || {
    echo "Failed to mount DMG" >&2
    exit 1
}

NEW_APP=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
if [[ -z "$NEW_APP" ]]; then
    echo "No app found in DMG" >&2
    exit 1
fi

BACKUP_PATH="${APP_PATH}.backup"
if [[ -d "$APP_PATH" ]]; then
    rm -rf "$BACKUP_PATH"
    mv "$APP_PATH" "$BACKUP_PATH"
fi

cp -R "$NEW_APP" "$APP_PATH" || {
    if [[ -d "$BACKUP_PATH" ]]; then
        mv "$BACKUP_PATH" "$APP_PATH"
    fi
    echo "Failed to install update" >&2
    exit 1
}

rm -rf "$BACKUP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

open -n "$APP_PATH" &
sleep 1
exit 0
