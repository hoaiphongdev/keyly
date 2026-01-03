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
    echo "Usage: $0 -t <template> [-n <name>]"
    echo ""
    echo "Options:"
    echo "  -t    Template name (required)"
    echo "  -n    Save as name (optional, defaults to template name)"
    echo ""
    echo "Example:"
    echo "  $0 -t cursor.keyly"
    echo "  $0 -t cursor.keyly -n my-cursor.keyly"
    exit 1
}

TEMPLATE=""
NAME=""

while getopts "t:n:h" opt; do
    case $opt in
        t) TEMPLATE="$OPTARG" ;;
        n) NAME="$OPTARG" ;;
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
    echo -e "${YELLOW}File '$NAME' already exists${NC}"
    echo ""
    echo "Choose action:"
    echo "  [r] Remove and replace"
    echo "  [b] Backup and replace"
    echo "  [c] Cancel"
    read -p "Action [r/b/c]: " action
    
    case $action in
        r|R)
            rm "$DEST"
            echo -e "${GREEN}Removed${NC} $DEST"
            ;;
        b|B)
            BACKUP="$DEST.backup.$(date +%Y%m%d%H%M%S)"
            mv "$DEST" "$BACKUP"
            echo -e "${GREEN}Backed up${NC} to $BACKUP"
            ;;
        *)
            echo "Cancelled"
            exit 0
            ;;
    esac
fi

echo -e "Downloading $TEMPLATE..."
if curl -sL "$RAW_URL" -o "$DEST"; then
    echo -e "${GREEN}✅ Installed${NC} $DEST"
else
    echo -e "${RED}Failed to download${NC}"
    exit 1
fi
