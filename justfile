default:
    @just --list

install:
    @which mise > /dev/null || (echo "❌ mise not found" && exit 1)
    @mise install
    rm -rf .build
    swift build -c release
    @echo "✅ Done"

# Run dev mode. Use 'just dev test-update' to mock update banner
dev *args:
    swift build
    @if [ "{{args}}" = "test-update" ]; then \
        KEYLY_DEV=1 KEYLY_MOCK_UPDATE=1 .build/debug/Keyly; \
    else \
        KEYLY_DEV=1 .build/debug/Keyly; \
    fi

prod:
    swift build -c release
    .build/release/Keyly

test-install:
    @pkill -x "Keyly" 2>/dev/null || true
    @rm -rf /Applications/Keyly.app
    @./scripts/install.sh .build/Keyly.dmg
    @open /Applications/Keyly.app

# One-time setup: generate Sparkle keys
setup-keys:
    swift build
    ./scripts/generate-keys.sh

release version:
    @test -n "{{version}}" || (echo "❌ Version required. Example: just release 1.0.0" && exit 1)
    @test -f sparkle_eddsa_public_key.txt || (echo "❌ Missing sparkle_eddsa_public_key.txt. Run 'just setup-keys' first." && exit 1)
    ./scripts/build-dmg.sh {{version}}
    ./scripts/update-appcast.sh {{version}}
    @echo ""
    @echo "✅ Release {{version}} ready!"
