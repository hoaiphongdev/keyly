default:
    @just --list

# Install dependencies and build
install:
    @which mise > /dev/null || (echo "❌ mise not found" && exit 1)
    @mise install
    rm -rf .build
    swift build -c release
    @echo "✅ Done"

# Build debug
build:
    swift build

# Build release
build-release:
    swift build -c release

# Run dev mode (shows shortcut window, no keyboard monitoring)
dev:
    swift build
    KEYLY_DEV=1 .build/debug/Keyly

# Run dev mode with mock update banner
dev-update:
    swift build
    KEYLY_DEV=1 KEYLY_MOCK_UPDATE=1 .build/debug/Keyly

# Run release build
prod:
    swift build -c release
    .build/release/Keyly

# Test the update check script locally
test-check-update version="1.0.0":
    @echo "🔍 Checking for updates (current: v{{version}})..."
    @./scripts/check-update.sh {{version}} && echo "" || echo ""

# Test update flow end-to-end (mock)
test-update-flow:
    @echo "🧪 Testing update flow..."
    @echo ""
    @echo "1. Build app..."
    swift build
    @echo ""
    @echo "2. Run with mock update..."
    @echo "   - Click 'Update Now' to test download simulation"
    @echo "   - Click 'Relaunch' to test relaunch"
    @echo ""
    KEYLY_DEV=1 KEYLY_MOCK_UPDATE=1 .build/debug/Keyly

# Install to /Applications from DMG
test-install:
    @pkill -x "Keyly" 2>/dev/null || true
    @rm -rf /Applications/Keyly.app
    @./scripts/install.sh .build/Keyly.dmg
    @open /Applications/Keyly.app

# Build DMG for release
build-dmg version:
    @test -n "{{version}}" || (echo "❌ Version required. Example: just build-dmg 1.0.0" && exit 1)
    @echo "🔨 Building Keyly v{{version}}..."
    ./scripts/build-dmg.sh {{version}}
    @echo ""
    @echo "✅ DMG ready: .build/Keyly.dmg"

# Build and verify release
release version:
    @test -n "{{version}}" || (echo "❌ Version required. Example: just release 1.0.0" && exit 1)
    @echo "🔨 Building Keyly v{{version}}..."
    @echo ""
    ./scripts/build-dmg.sh {{version}}
    @echo ""
    @echo "🔍 Verifying build..."
    ./scripts/verify-build.sh
    @echo ""
    @echo "✅ Release v{{version}} ready!"
    @echo ""
    @echo "📦 Next steps:"
    @echo "   1. Create GitHub release: gh release create v{{version}} .build/Keyly.dmg"
    @echo "   2. Or upload .build/Keyly.dmg manually to GitHub Releases"

# Clean build artifacts
clean:
    rm -rf .build
    @echo "✅ Cleaned"

# Show current version from Info.plist (if exists)
version:
    @grep -A1 CFBundleShortVersionString Sources/Keyly/Resources/Info.plist 2>/dev/null | tail -1 | sed 's/.*<string>//;s/<\/string>.*//' || echo "Version not found in Info.plist"
