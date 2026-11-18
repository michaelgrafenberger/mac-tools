#!/bin/bash
# Live read-only measurements plus SIGTERM/SIGKILL on this test's own /bin/sleep children only.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/Build/ModuleCache"
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/Build/ModuleCache" \
  "$PROJECT_DIR/Sources/RAMUsage/Memory.swift" "$PROJECT_DIR/Sources/RAMUsage/Processes.swift" \
  "$PROJECT_DIR/Tests/RAM/main.swift" -framework Cocoa -o "$PROJECT_DIR/Build/ram-tests"
"$PROJECT_DIR/Build/ram-tests"
