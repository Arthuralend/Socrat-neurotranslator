#!/bin/bash
# Запускает сервер перевода прямо из собранного приложения и проверяет перевод.
#   scripts/smoke_test.sh <путь к Сократ.app>
set -euo pipefail

RES="$1/Contents/Resources"
PORT=8799
"$RES/python/bin/python3" -I -B "$RES/translate_server.py" --model "$RES/model" --port $PORT &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT

for _ in $(seq 1 120); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break
  sleep 1
done
curl -sf "http://127.0.0.1:$PORT/health"; echo
echo "Языков: $(curl -sf "http://127.0.0.1:$PORT/languages" | grep -o '_' | wc -l)"

translate() {
  local out
  out="$(curl -sf -X POST "http://127.0.0.1:$PORT/translate" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"$3\", \"source\": \"$1\", \"target\": \"$2\"}")"
  echo "$1 -> $2: $3  =>  $out"
  [[ "$out" == *translation* ]]
}
translate eng_Latn rus_Cyrl "Select text and press Command C twice."
translate rus_Cyrl hye_Armn "Привет! Как дела?"
translate hye_Armn eng_Latn "Բարև, ինչպե՞ս ես։"
translate deu_Latn spa_Latn "Ich lerne gerne neue Sprachen."
echo "OK"
