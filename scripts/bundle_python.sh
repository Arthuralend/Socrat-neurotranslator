#!/bin/bash
# Готовит автономный Python (python-build-standalone) с движком перевода
# для встраивания в приложение. Запускается в CI на macOS.
#   scripts/bundle_python.sh <выходная_папка>
set -euo pipefail

OUT="$1"
PYVER="3.12"
case "$(uname -m)" in
  arm64) ARCH=aarch64 ;;
  x86_64) ARCH=x86_64 ;;
esac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

URL="$(gh api repos/astral-sh/python-build-standalone/releases/latest \
  --jq '.assets[].browser_download_url' \
  | grep -E "/cpython-${PYVER//./\\.}\.[0-9]+\+[0-9]+-${ARCH}-apple-darwin-install_only\.tar\.gz$" \
  | head -1)"
[[ -n "$URL" ]] || { echo "Не найден Python $PYVER для $ARCH"; exit 1; }
echo "Python: $URL"

rm -rf "$OUT" && mkdir -p "$OUT"
curl -fsSL "$URL" | tar -xz -C "$OUT" --strip-components=1

PY="$OUT/bin/python3"
"$PY" -m pip install -q --no-warn-script-location -r "$ROOT/server/requirements.txt"
"$PY" -m pip uninstall -q -y pip

# Убираем то, что серверу перевода не нужно (тесты, IDLE, Tk, заголовки).
LIB="$OUT/lib/python$PYVER"
rm -rf "$LIB"/{test,idlelib,tkinter,turtledemo,ensurepip,lib2to3} \
       "$LIB"/lib-dynload/_tkinter* \
       "$OUT"/lib/{tcl,tk,itcl,thread}* "$OUT"/share "$OUT"/include
find "$OUT" -name "__pycache__" -type d -prune -exec rm -rf {} +
"$PY" -m compileall -q -j 0 "$LIB" >/dev/null || true

du -sh "$OUT"
