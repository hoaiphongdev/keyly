#!/bin/bash
set -eo pipefail

GITHUB_REPO="hoaiphongdev/keyly"
CURRENT_VERSION="${1:-}"

if [[ -z "$CURRENT_VERSION" ]]; then
    echo '{"error": "No version provided"}' >&2
    exit 1
fi

RELEASE_JSON=$(curl -sS --connect-timeout 10 --max-time 30 \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) || {
    echo '{"error": "Failed to fetch release info"}' >&2
    exit 2
}

TAG_NAME=$(echo "$RELEASE_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/"$//' || echo "")
LATEST_VERSION=$(echo "$TAG_NAME" | sed 's/^v//')

DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.dmg"' | head -1 | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"//;s/"$//' || echo "")

if [[ -z "$LATEST_VERSION" ]]; then
    echo '{"error": "Could not parse version from release"}' >&2
    exit 1
fi

version_gt() {
    local IFS=.
    local i ver1=($1) ver2=($2)
    
    for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
        local v1=${ver1[i]:-0}
        local v2=${ver2[i]:-0}
        if ((v1 > v2)); then return 0; fi
        if ((v1 < v2)); then return 1; fi
    done
    return 1
}

if version_gt "$LATEST_VERSION" "$CURRENT_VERSION"; then
    cat <<EOF
{
    "updateAvailable": true,
    "currentVersion": "$CURRENT_VERSION",
    "latestVersion": "$LATEST_VERSION",
    "downloadUrl": "$DOWNLOAD_URL"
}
EOF
    exit 0
else
    cat <<EOF
{
    "updateAvailable": false,
    "currentVersion": "$CURRENT_VERSION",
    "latestVersion": "$LATEST_VERSION"
}
EOF
    exit 1
fi
