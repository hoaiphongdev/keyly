default:
    @just --list

install:
    @which mise > /dev/null || (echo "❌ mise not found" && exit 1)
    @mise install
    rm -rf .build
    swift build -c release
    @echo "✅ Done"

dev:
    swift build
    KEYLY_DEV=1 .build/debug/Keyly

# Test with mock update banner
dev-update:
    swift build
    KEYLY_DEV=1 KEYLY_MOCK_UPDATE=1 .build/debug/Keyly

prod:
    swift build -c release
    .build/release/Keyly

release version:
    @[ -n "{{version}}" ] || (echo "❌ version not set" && exit 1)
    @./scripts/build-dmg.sh {{version}}

test-install:
    @pkill -x "Keyly" 2>/dev/null || true
    @rm -rf /Applications/Keyly.app
    @./scripts/install.sh .build/Keyly.dmg
    @open /Applications/Keyly.app

# One-time setup: generate Sparkle keys
setup-keys:
    swift build
    ./scripts/generate-keys.sh