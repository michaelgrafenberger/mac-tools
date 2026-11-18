#!/bin/bash
# Renders the actual native SwiftUI views, using clearly marked, synthetic preview data.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/Preview"
for NAME in Fokus Offen Grid NetSpeed RAMUsage; do
  for APPEARANCE in light dark; do
    "$PROJECT_DIR/Build/$NAME.app/Contents/MacOS/$NAME" \
      --preview "--$APPEARANCE" --screenshot "$PROJECT_DIR/Preview/$NAME-$APPEARANCE.png"
  done
done
