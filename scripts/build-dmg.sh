#!/bin/bash
set -e

APP_NAME="Keyly"
VERSION="${1:-1.0.0}"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_DIR=".build/dmg"
ICON_DIR=".build/icons"

echo "🔨 Building $APP_NAME v$VERSION..."

swift build -c release

echo "🎨 Creating app icon..."

rm -rf "$ICON_DIR"
mkdir -p "$ICON_DIR/AppIcon.iconset"

PNG_FILE="Sources/Keyly/Resources/keyly.png"

if [ -f "$PNG_FILE" ]; then
    sips -z 16 16 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_16x16.png" > /dev/null
    sips -z 32 32 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_16x16@2x.png" > /dev/null
    sips -z 32 32 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_32x32.png" > /dev/null
    sips -z 64 64 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_32x32@2x.png" > /dev/null
    sips -z 128 128 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_128x128.png" > /dev/null
    sips -z 256 256 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_128x128@2x.png" > /dev/null
    sips -z 256 256 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_256x256.png" > /dev/null
    sips -z 512 512 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_256x256@2x.png" > /dev/null
    sips -z 512 512 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$PNG_FILE" --out "$ICON_DIR/AppIcon.iconset/icon_512x512@2x.png" > /dev/null
    
    iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "$ICON_DIR/AppIcon.icns"
    echo "   ✅ Icon created"
else
    echo "   ⚠️ No PNG found, skipping icon"
fi

echo "📦 Creating app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

if [ -d "$BUILD_DIR/Keyly_Keyly.bundle" ]; then
    cp -r "$BUILD_DIR/Keyly_Keyly.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -f "$ICON_DIR/AppIcon.icns" ]; then
    cp "$ICON_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    ICON_FILE="AppIcon"
else
    ICON_FILE=""
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.keyly.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024</string>
</dict>
</plist>
EOF

echo "💿 Creating DMG..."

rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -r "$APP_BUNDLE" "$DMG_DIR/"

rm -f ".build/$DMG_NAME"

create-dmg \
    --volname "$APP_NAME" \
    --volicon "$ICON_DIR/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 450 190 \
    ".build/$DMG_NAME" \
    "$DMG_DIR/"

rm -rf "$DMG_DIR"
rm -rf "$ICON_DIR"

echo ""
echo "✅ Build complete!"
echo "   App: $APP_BUNDLE"
echo "   DMG: .build/$DMG_NAME"
