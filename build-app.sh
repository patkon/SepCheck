#!/bin/bash
# Baut SepCheck.app – benötigt nur die Xcode Command Line Tools (xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

echo "→ Kompiliere (Release) …"
swift build -c release

APP="SepCheck.app"
BIN="$(swift build -c release --show-bin-path)/SepCheck"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SepCheck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

echo "→ Erzeuge Icon …"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
# Bis 64 px die vereinfachte Lupe, ab 128 px das detaillierte Motiv
src_for() { if [ "$1" -le 64 ]; then echo Resources/icon-small.png; else echo Resources/icon-1024.png; fi; }
for s in 16 32 128 256 512; do
  sips -z $s $s "$(src_for $s)" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$(src_for $d)" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signiere (ad hoc) …"
codesign --force --deep --sign - "$APP"

if ! command -v gs >/dev/null && [ ! -x /opt/homebrew/bin/gs ] && [ ! -x /usr/local/bin/gs ]; then
  echo ""
  echo "⚠︎  Ghostscript fehlt noch:  brew install ghostscript"
fi

echo ""
echo "✓ Fertig: $(pwd)/$APP"
echo "  Zum Installieren nach /Programme ziehen oder:  open $APP"
