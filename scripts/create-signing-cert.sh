#!/bin/bash
# Create the stable self-signed code signing certificate for Keyly. Run ONCE.
#
# macOS keeps the Accessibility grant as long as every release is signed with
# this same certificate. Losing or replacing it resets the grant for every user,
# so back up the output folder and never regenerate it casually.
set -euo pipefail

OUT_DIR="${1:-$HOME/.keyly-signing}"
NAME="Keyly Self-Signed"
DAYS=3650

if [[ -f "$OUT_DIR/keyly-signing.p12" ]]; then
    echo "❌ $OUT_DIR/keyly-signing.p12 already exists. Refusing to overwrite the signing identity." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

cat > "$OUT_DIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
    -keyout "$OUT_DIR/key.pem" -out "$OUT_DIR/cert.pem" -config "$OUT_DIR/cert.cnf" 2>/dev/null

PASSWORD=$(openssl rand -base64 24)
# -legacy: macOS `security import` cannot read OpenSSL 3's default p12 encryption.
openssl pkcs12 -export -legacy -name "$NAME" \
    -inkey "$OUT_DIR/key.pem" -in "$OUT_DIR/cert.pem" \
    -out "$OUT_DIR/keyly-signing.p12" -passout "pass:$PASSWORD"

echo "$PASSWORD" > "$OUT_DIR/p12-password.txt"
rm "$OUT_DIR/key.pem" "$OUT_DIR/cert.cnf"
chmod 600 "$OUT_DIR"/*

SHA1=$(openssl x509 -in "$OUT_DIR/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)

echo "✅ Created $OUT_DIR/keyly-signing.p12"
echo ""
echo "Identity SHA-1 (use as KEYLY_SIGN_IDENTITY): $SHA1"
echo ""
echo "GitHub secrets:"
echo "  KEYLY_CERT_P12_BASE64 = base64 -i $OUT_DIR/keyly-signing.p12 | pbcopy"
echo "  KEYLY_CERT_PASSWORD   = cat $OUT_DIR/p12-password.txt | pbcopy"
echo ""
echo "⚠️  Back up $OUT_DIR somewhere safe (password manager). It is not recoverable."
