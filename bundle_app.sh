#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

xcrun swift build -c release

BIN_PATH="$(xcrun swift build -c release --show-bin-path)/BrightspaceSync"
APP_DIR="$SCRIPT_DIR/BrightspaceSync.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/BrightspaceSync"
if [[ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BrightspaceSync</string>
    <key>CFBundleIdentifier</key>
    <string>com.brightspacepulse.app</string>
    <key>CFBundleName</key>
    <string>Brightspace Pulse</string>
    <key>CFBundleDisplayName</key>
    <string>Brightspace Pulse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"
echo "Built menu bar app bundle at: $APP_DIR"
