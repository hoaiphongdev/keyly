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
ditto "$MOUNT_POINT/Keyly.app" /Applications/Keyly.app

echo "🔓 Removing quarantine attribute..."
xattr -cr /Applications/Keyly.app

echo "🔌 Unmounting..."
hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true

echo "🧹 Cleaning up..."
rm -f /tmp/Keyly.dmg

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║                  ✅ Keyly installed successfully!          ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}${BOLD}🚀 Getting started:${NC}"
echo -e "   ${BOLD}1.${NC} Open Spotlight ${CYAN}${BOLD}⌘ + Space${NC}, search ${BOLD}'Keyly'${NC} and open it"
echo -e "   ${BOLD}2.${NC} Grant ${BOLD}Accessibility${NC} permission when prompted"
echo -e "   ${BOLD}3.${NC} Done! Double-tap ${CYAN}⇪ Caps Lock${NC} to show shortcuts"
echo ""
echo -e "${YELLOW}⚠️  If shortcuts don't work:${NC}"
echo -e "   ${DIM}System Settings → Privacy & Security → Accessibility${NC}"
echo -e "   ${DIM}Remove Keyly if listed, then re-add it.${NC}"
echo ""

