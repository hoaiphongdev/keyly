#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION="$1"
DMG_PATH=".build/Keyly.dmg"
APPCAST="docs/appcast.xml"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
PRIVATE_KEY_FILE="sparkle_eddsa_private_key.txt"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH"
    exit 1
fi

if [ ! -f "$APPCAST" ]; then
    echo "❌ Appcast not found: $APPCAST"
    exit 1
fi

# Get signature
if [ -f "$PRIVATE_KEY_FILE" ]; then
    SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH" -f "$PRIVATE_KEY_FILE")
else
    SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
fi

# Extract signature and length
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
FILE_SIZE=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

# Validate extraction
if [ -z "$SIGNATURE" ] || [ -z "$FILE_SIZE" ]; then
    echo "❌ Failed to extract signature or file size"
    echo "Output was: $SIGN_OUTPUT"
    exit 1
fi

PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")

# Backup appcast
cp "$APPCAST" "$APPCAST.bak"

# Use Python to update appcast
python3 - "$VERSION" "$PUB_DATE" "$SIGNATURE" "$FILE_SIZE" "$APPCAST" << 'PYEOF'
import sys
import re

version = sys.argv[1]
pub_date = sys.argv[2]
signature = sys.argv[3]
file_size = sys.argv[4]
appcast_path = sys.argv[5]

new_item = f'''
        <!-- Latest Release -->
        <item>
            <title>Version {version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h2>What's New in {version}</h2>
                <p>
                    <a href="https://github.com/hoaiphongdev/keyly/blob/main/CHANGELOG.md">
                        View full changelog on GitHub
                    </a>
                </p>
            ]]></description>
            <enclosure 
                url="https://github.com/hoaiphongdev/keyly/releases/download/v{version}/Keyly.dmg"
                sparkle:edSignature="{signature}"
                length="{file_size}"
                type="application/octet-stream"/>
        </item>
'''

with open(appcast_path, 'r') as f:
    content = f.read()

# Remove ALL old items (including extra whitespace)
content = re.sub(r'\s*<!-- .*?Release.*?-->\s*<item>.*?</item>\s*', '', content, flags=re.DOTALL)

# Insert new item after <language>en</language>
if '<language>en</language>' not in content:
    print("❌ Could not find <language>en</language> in appcast.xml")
    sys.exit(1)

content = content.replace('<language>en</language>', '<language>en</language>' + new_item, 1)

# Clean up extra blank lines before </channel>
content = re.sub(r'\n\s*\n\s*</channel>', '\n    </channel>', content)

with open(appcast_path, 'w') as f:
    f.write(content)

print(f"✅ Appcast updated successfully")
PYEOF

if [ $? -eq 0 ]; then
    echo "✅ Appcast updated:"
    echo "   Version: $VERSION"
    echo "   Signature: ${SIGNATURE:0:50}..."
    echo "   Length: $FILE_SIZE bytes"
    rm "$APPCAST.bak"
else
    echo "❌ Failed to update appcast, restoring backup"
    mv "$APPCAST.bak" "$APPCAST"
    exit 1
fi