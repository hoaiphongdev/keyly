#!/bin/bash
# Print the CHANGELOG.md section for one version (without its heading).
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

# Prereleases (1.8.0-rc1) reuse the notes of the version they lead to.
VERSION="${VERSION%%-*}"

NOTES=$(awk -v v="$VERSION" '
    index($0, "## [" v "]") == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md)

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
    echo "❌ No '## [$VERSION]' section in CHANGELOG.md" >&2
    exit 1
fi

echo "$NOTES"
