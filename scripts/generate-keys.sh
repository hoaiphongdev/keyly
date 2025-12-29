#!/bin/bash
# Generate EdDSA key pair for Sparkle updates

set -e

SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY_FILE="sparkle_eddsa_public_key.txt"
PRIVATE_KEY_FILE="sparkle_eddsa_private_key.txt"

echo "Generating EdDSA key pair for Sparkle..."

if [ ! -d "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle not found. Run 'swift build' first to fetch dependencies."
    exit 1
fi

# Generate keys (or get existing) and print public key
OUTPUT=$("$SPARKLE_BIN/generate_keys" 2>&1)
echo "$OUTPUT"

# Extract public key
PUBLIC_KEY=$(echo "$OUTPUT" | grep -A1 "SUPublicEDKey" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

if [ -n "$PUBLIC_KEY" ]; then
    echo "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"
    echo ""
    echo "✅ Public key saved to: $PUBLIC_KEY_FILE"
else
    echo "❌ Could not extract public key."
    exit 1
fi

# Export private key to file
echo ""
echo "🔑 Exporting private key..."
"$SPARKLE_BIN/generate_keys" -x "$PRIVATE_KEY_FILE"
echo "✅ Private key saved to: $PRIVATE_KEY_FILE"
echo ""
echo "⚠️  $PRIVATE_KEY_FILE is gitignored. Keep it safe!"
