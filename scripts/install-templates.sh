#!/bin/bash
set -e

REPO="hoaiphongdev/keyly"
BRANCH="main"
TEMPLATES_PATH="templates"
CONFIG_DIR="$HOME/.config/keyly"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 -t <template> [-n <name>] [-f]"
    echo ""
    echo "Options:"
    echo "  -t    Template name (required)"
    echo "  -n    Save as name (optional)"
    echo "  -f    Force replace if exists"
    echo ""
    echo "Example:"
    echo "  $0 -t cursor.keyly"
    echo "  $0 -t cursor.keyly -f"
    exit 1
}

TEMPLATE=""
NAME=""
FORCE=false

while getopts "t:n:fh" opt; do
    case $opt in
        t) TEMPLATE="$OPTARG" ;;
        n) NAME="$OPTARG" ;;
        f) FORCE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$TEMPLATE" ]; then
    echo -e "${RED}Error: Template name is required${NC}"
    usage
fi

if [ -z "$NAME" ]; then
    NAME="$TEMPLATE"
fi

[[ "$NAME" != *.keyly ]] && NAME="$NAME.keyly"

mkdir -p "$CONFIG_DIR"

RAW_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/$TEMPLATES_PATH/$TEMPLATE"
HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "$RAW_URL")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}Error: Template '$TEMPLATE' not found${NC}"
    exit 1
fi

DEST="$CONFIG_DIR/$NAME"

if [ -f "$DEST" ]; then
    if [ "$FORCE" = true ]; then
        rm "$DEST"
        echo -e "${YELLOW}Replaced${NC} existing file"
    else
        echo -e "${RED}Error: File '$NAME' already exists${NC}"
        echo "Use -f to force replace"
        exit 1
    fi
fi

echo -e "Downloading $TEMPLATE..."
if curl -sL "$RAW_URL" -o "$DEST"; then
    echo -e "${GREEN}✅ Installed${NC} $DEST"
else
    echo -e "${RED}Failed to download${NC}"
    exit 1
fi
