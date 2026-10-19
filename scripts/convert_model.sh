#!/bin/bash
# Скачивает NLLB-200 с Hugging Face и конвертирует в CTranslate2 int8.
# Запускается в CI (Linux), на компьютере пользователя не нужен.
#   scripts/convert_model.sh <выходная_папка> [hf_модель]
set -euo pipefail

OUT="$1"
HF_MODEL="${2:-facebook/nllb-200-distilled-1.3B}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}/convert"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 -m venv "$WORK/venv"
PY="$WORK/venv/bin/python"
"$PY" -m pip install -q --upgrade pip
"$PY" -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu
"$PY" -m pip install -q "ctranslate2>=4.3" "transformers>=4.46,<5" sentencepiece protobuf

rm -rf "$OUT"
HF_HOME="$WORK/hf" "$WORK/venv/bin/ct2-transformers-converter" \
  --model "$HF_MODEL" \
  --quantization int8 \
  --copy_files sentencepiece.bpe.model \
  --output_dir "$OUT"
rm -rf "$WORK/hf"

echo "Проверка модели:"
"$PY" "$ROOT/scripts/check_model.py" "$OUT"
du -sh "$OUT"
