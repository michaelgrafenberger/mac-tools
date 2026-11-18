#!/bin/bash
# Creates and closes only its own three fixture windows. Never requests Accessibility permission.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/Build/ModuleCache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PROJECT_DIR/Build/ModuleCache" \
  "$PROJECT_DIR/Sources/Shared/Logic.swift" "$PROJECT_DIR/Sources/Offen/BadgeReader.swift" \
  "$PROJECT_DIR/Sources/Grid/WindowAccess.swift" "$PROJECT_DIR/Tests/NativeProbe.swift" \
  -framework Cocoa -framework ApplicationServices -o "$PROJECT_DIR/Build/native-probe"
"$PROJECT_DIR/Build/native-probe"
