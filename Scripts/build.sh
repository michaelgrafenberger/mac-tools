#!/bin/bash
# Builds into this project only. Does not install, replace, launch, or stop any app.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_OUTPUT:-$PROJECT_DIR/Build}"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
mkdir -p "$BUILD_DIR/ModuleCache"

if [ "$#" -eq 0 ]; then set -- Fokus Offen Grid NetSpeed RAMUsage; fi
for NAME in "$@"; do
  case "$NAME" in
    Fokus) SYMBOL="circle.inset.filled" ;;
    Offen) SYMBOL="tray" ;;
    Grid) SYMBOL="rectangle.split.2x2" ;;
    NetSpeed) SYMBOL="arrow.down" ;;
    RAMUsage) SYMBOL="memorychip" ;;
    *) echo "Unknown app: $NAME" >&2; exit 1 ;;
  esac
  APP_DIR="$BUILD_DIR/$NAME.app"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
  echo "Building $NAME ($ARCH, macOS 13+)…"
  xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos13.0" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "$PROJECT_DIR"/Sources/Shared/*.swift "$PROJECT_DIR"/Sources/"$NAME"/*.swift \
    -o "$APP_DIR/Contents/MacOS/$NAME" \
    -framework Cocoa -framework SwiftUI -framework Carbon -framework ServiceManagement -framework ApplicationServices
  LOWER_NAME="$(echo "$NAME" | tr '[:upper:]' '[:lower:]')"
  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>at.grafenberger.tools.$LOWER_NAME</string>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>© 2026 Grafenberger</string>
</dict></plist>
PLIST
  if [ -f "$PROJECT_DIR/Assets/$NAME.icns" ]; then cp "$PROJECT_DIR/Assets/$NAME.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
  codesign --force --sign - "$APP_DIR"
  codesign --verify --strict "$APP_DIR"
done
echo "Builds ready: $BUILD_DIR"
