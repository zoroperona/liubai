#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ARGS=(-c release -Xswiftc -file-prefix-map -Xswiftc "$PWD=/src/PlanIsland")
swift build "${BUILD_ARGS[@]}" "$@"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" "$@" --show-bin-path)"
APP="$PWD/dist/留白.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PlanIsland" "$APP/Contents/MacOS/PlanIsland"
# Distribute executable code without local debug paths or build metadata.
strip -S "$APP/Contents/MacOS/PlanIsland"
mkdir -p .build/AppIcon.iconset
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>留白</string>
  <key>CFBundleDisplayName</key><string>留白</string>
  <key>CFBundleExecutable</key><string>PlanIsland</string>
  <key>CFBundleIdentifier</key><string>local.planisland.app</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>local.planisland.plan-id</string>
    <key>UTTypeDescription</key><string>留白计划排序</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built: $APP"
