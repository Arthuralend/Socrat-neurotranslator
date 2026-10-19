#!/bin/bash
# Собирает «Сократ.app» со встроенными Python и моделью.
#   scripts/build_app.sh <папка_python> <папка_модели> [выход]
set -euo pipefail

PYDIR="$1"
MODEL="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="${3:-$ROOT/build}"
APP="$OUTDIR/Сократ.app"
VERSION="${VERSION:-1.0.0}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/Sokrat" \
  "$ROOT"/app/Sources/*.swift

cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/server/translate_server.py" "$APP/Contents/Resources/"
cp -R "$PYDIR" "$APP/Contents/Resources/python"
cp -R "$MODEL" "$APP/Contents/Resources/model"

# Ad-hoc подпись: сначала все вложенные бинарники Python, затем само приложение.
find "$APP/Contents/Resources/python" -type f \( -perm -u+x -o -name "*.so" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q "Mach-O"; then codesign --force --sign - "$f"; fi
  done
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
du -sh "$APP"
