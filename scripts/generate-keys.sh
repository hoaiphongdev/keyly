#!/bin/bash
# Generate the EdDSA key pair Sparkle uses to verify updates. Run ONCE.
# The private key also stays in your login Keychain (Sparkle's default).
set -euo pipefail

SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY_FILE="sparkle_eddsa_public_key.txt"
OUT_DIR="${1:-$HOME/.keyly-signing}"
PRIVATE_KEY_FILE="$OUT_DIR/sparkle_eddsa_private_key.txt"

if [ ! -d "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle not found. Run 'swift build' first to fetch dependencies."
    exit 1
fi

if [ -f "$PRIVATE_KEY_FILE" ]; then
    echo "❌ $PRIVATE_KEY_FILE already exists. Refusing to overwrite."
    exit 1
fi

"$SPARKLE_BIN/generate_keys" --account keyly
"$SPARKLE_BIN/generate_keys" --account keyly -p > "$PUBLIC_KEY_FILE"
echo "✅ Public key saved to: $PUBLIC_KEY_FILE (commit this)"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
"$SPARKLE_BIN/generate_keys" --account keyly -x "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"
echo "✅ Private key saved to: $PRIVATE_KEY_FILE"
echo ""
echo "GitHub secret SPARKLE_PRIVATE_KEY = cat $PRIVATE_KEY_FILE | pbcopy"
echo "⚠️  Back it up. Losing it means installed copies can no longer verify updates."
