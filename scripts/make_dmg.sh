#!/bin/bash
# Упаковывает приложение в .dmg с ярлыком «Программы» для перетаскивания.
#   scripts/make_dmg.sh <путь к Сократ.app> <выход.dmg>
set -euo pipefail

APP="$1"
DMG="$2"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Сократ" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG"
rm -rf "$STAGE"
ls -lh "$DMG"
