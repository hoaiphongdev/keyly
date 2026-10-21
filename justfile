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

# Run tests (swift-testing macros need the Xcode toolchain, not just Command Line Tools)
test:
    DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift test

alias run := dev

# Run dev mode (shows shortcut window, no keyboard monitoring)
dev:
    swift build
    KEYLY_DEV=1 .build/debug/Keyly

# Run release build
prod:
    swift build -c release
    .build/release/Keyly

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

# Build and verify a release locally (signs ad-hoc unless KEYLY_SIGN_IDENTITY is set)
release-local version:
    @test -n "{{version}}" || (echo "❌ Version required. Example: just release-local 1.0.0" && exit 1)
    ./scripts/build-dmg.sh {{version}}
    ./scripts/verify-build.sh

# Publish a release: tag + push, GitHub Actions builds, signs and uploads it
release version:
    @test -n "{{version}}" || (echo "❌ Version required. Example: just release 1.8.0" && exit 1)
    @./scripts/release-notes.sh {{version}} > /dev/null
    @test -z "$(git status --porcelain)" || (echo "❌ Working tree is not clean. Commit first." && exit 1)
    git tag -m "Keyly {{version}}" keyly-{{version}}
    git push origin keyly-{{version}}
    @echo "🚀 Tag pushed. Follow the build: gh run watch"

# One-time setup: create the self-signed signing cert and Sparkle EdDSA keys
setup-signing:
    ./scripts/create-signing-cert.sh
    swift build
    ./scripts/generate-keys.sh

# Clean build artifacts
clean:
    rm -rf .build
    @echo "✅ Cleaned"

# Show current version from Info.plist (if exists)
version:
    @grep -A1 CFBundleShortVersionString Sources/Keyly/Resources/Info.plist 2>/dev/null | tail -1 | sed 's/.*<string>//;s/<\/string>.*//' || echo "Version not found in Info.plist"
