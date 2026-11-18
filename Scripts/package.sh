#!/bin/bash
# Local preview packages only. Does not upload or publish anything.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/Dist"
COLLECTION_DIR="$DIST_DIR/Mac Tools Preview"
mkdir -p "$COLLECTION_DIR"
for NAME in Fokus Offen Grid NetSpeed RAMUsage; do
  APP_DIR="$PROJECT_DIR/Build/$NAME.app"
  codesign --verify --strict "$APP_DIR"
  ARCHITECTURE="$(lipo -archs "$APP_DIR/Contents/MacOS/$NAME")"
  if [ "$ARCHITECTURE" != "arm64" ]; then echo "Expected arm64 preview build: $NAME" >&2; exit 1; fi
  ditto "$APP_DIR" "$COLLECTION_DIR/$NAME.app"
  ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/$NAME-0.3.0-preview-arm64.zip"
done
cat > "$COLLECTION_DIR/LIESMICH.txt" <<'INFO'
MAC TOOLS · 0.3.0 · Lokale Entwicklungsvorschau · Apple Silicon

Fokus, Offen, Grid, NetSpeed und RAM sind einzelne Apps mit gemeinsamer Gestaltung.
Die ursprünglichen Apps wurden nicht ersetzt. Zum Ausprobieren die gewünschte
App hier im Finder öffnen. Alte und neue Version nicht gleichzeitig nutzen.

Einstellungen: Schieberegler-Symbol unten rechts. Menübar-Icons sind optional.
Ohne Icon die App per Finder oder Spotlight erneut öffnen.

Tastenkürzel:
Fokus:    Command + Shift + F (Fokus ein/aus)
Offen:    Control + Option + O
Grid:     Control + Option + G
NetSpeed: Control + Option + N
RAM:      Control + Option + R

Grid benötigt für echte Fensterbewegungen die Bedienungshilfen-Freigabe.
Fokus benötigt für die optionale Mitteilungspause eigene Kurzbefehle.
Die Freigaben und Kurzbefehle werden nicht automatisch eingerichtet.

Diese lokalen Builds sind ad hoc signiert, nicht mit Developer ID signiert
oder notarisiert. Sie sind noch kein öffentlicher Release. Bei einer späteren
Internetverteilung kann macOS den Start blockieren. Keine Sicherheitseinstellungen
abschalten; für den öffentlichen Download ist ein separater Release vorgesehen.

Quellcode, Anleitung, Gestaltung und Prüfstand liegen im Projekt mac-tools.
INFO
ditto -c -k --keepParent "$COLLECTION_DIR" "$DIST_DIR/Mac-Tools-0.3.0-preview-arm64.zip"
python3 - "$PROJECT_DIR" "$DIST_DIR/Mac-Tools-0.3.0-source.zip" <<'PY'
import pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if path.is_file() and not any(part in {'Build', 'Dist', '.git', '.DS_Store'} for part in relative.parts):
            archive.write(path, pathlib.Path('mac-tools') / relative)
PY
echo "Local packages ready: $DIST_DIR"
