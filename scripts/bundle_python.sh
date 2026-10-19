#!/bin/bash
# Готовит автономный Python (python-build-standalone) с движком перевода
# для встраивания в приложение. Запускается в CI на macOS.
#   scripts/bundle_python.sh <выходная_папка>
set -euo pipefail

OUT="$1"
PYVER="3.12"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"

# uv скачивает готовую сборку python-build-standalone (переносимый Python).
python3 -m venv "$WORK/uv"
"$WORK/uv/bin/pip" install -q uv
UV="$WORK/uv/bin/uv"
UV_PYTHON_INSTALL_DIR="$WORK/pythons" "$UV" python install "$PYVER"
SRC="$(find "$WORK/pythons" -maxdepth 1 -type d -name "cpython-$PYVER*" | head -1)"
[[ -n "$SRC" ]] || { echo "uv не установил Python $PYVER"; exit 1; }

rm -rf "$OUT" && mkdir -p "$(dirname "$OUT")"
cp -R "$SRC" "$OUT"
trap 'rm -rf "$WORK"' EXIT

PY="$OUT/bin/python3"
rm -f "$OUT/lib/python$PYVER/EXTERNALLY-MANAGED"
"$UV" pip install --python "$PY" --break-system-packages -r "$ROOT/server/requirements.txt"
"$PY" -m pip uninstall -q -y pip 2>/dev/null || true
"$PY" -c "import ctranslate2, sentencepiece; print('ctranslate2', ctranslate2.__version__)"

# Убираем то, что серверу перевода не нужно (тесты, IDLE, Tk, заголовки).
LIB="$OUT/lib/python$PYVER"
rm -rf "$LIB"/{test,idlelib,tkinter,turtledemo,ensurepip,lib2to3} \
       "$LIB"/lib-dynload/_tkinter* \
       "$OUT"/lib/{tcl,tk,itcl,thread,libtcl,libtk}* "$OUT"/share "$OUT"/include
find "$OUT" -name "__pycache__" -type d -prune -exec rm -rf {} +
"$PY" -m compileall -q -j 0 "$LIB" >/dev/null || true

du -sh "$OUT"
