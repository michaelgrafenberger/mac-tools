#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/Build/ModuleCache"
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/Build/ModuleCache" \
  "$PROJECT_DIR/Sources/Shared/Logic.swift" "$PROJECT_DIR/Sources/NetSpeed/NetworkReader.swift" \
  "$PROJECT_DIR/Sources/Offen/BadgeReader.swift" \
  "$PROJECT_DIR/Tests/main.swift" -o "$PROJECT_DIR/Build/logic-tests"
"$PROJECT_DIR/Build/logic-tests" "$@"
