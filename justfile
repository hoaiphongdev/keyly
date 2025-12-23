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

prod:
    swift build -c release
    .build/release/Keyly

release version:
    @[ -n "{{version}}" ] || (echo "❌ version not set" && exit 1)
    @./scripts/build-dmg.sh {{version}}
