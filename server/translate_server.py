#!/usr/bin/env python3
"""Локальный сервер перевода для «Сократа».

Модель: Meta NLLB-200 (конвертированная в CTranslate2, int8), ~200 языков.
Работает полностью офлайн, слушает только 127.0.0.1.

API:
  GET  /health     -> {"ready": true, "model": "..."}
  GET  /languages  -> {"languages": ["eng_Latn", "rus_Cyrl", ...]}
  POST /translate {"text", "source", "target"} -> {"translation": "..."}
       source/target — коды FLORES-200, например eng_Latn, rus_Cyrl, hye_Armn
"""

import argparse
import json
import os
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import ctranslate2
import sentencepiece as spm

# Длинные строки режем на предложения: NLLB лучше всего переводит фрагменты до ~200 токенов.
MAX_SEGMENT_TOKENS = 200
SENTENCE_SPLIT = re.compile(r"(?<=[.!?…։;。！？])\s*(?=\S)")
LANG_CODE = re.compile(r"^[a-z]{3}_[A-Z][a-z]{3}$")


def load_language_codes(model_dir: str) -> list:
    """Коды языков — это специальные токены вида xxx_Yyyy в словаре модели."""
    for name in ("shared_vocabulary.json", "shared_vocabulary.txt"):
        path = os.path.join(model_dir, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            if name.endswith(".json"):
                vocab = json.load(f)
            else:
                vocab = [line.rstrip("\n") for line in f]
        return sorted(t for t in vocab if LANG_CODE.match(t))
    raise FileNotFoundError(f"В {model_dir} нет shared_vocabulary.json")


class Translator:
    def __init__(self, model_dir: str, device: str, threads: int):
        sp_path = os.path.join(model_dir, "sentencepiece.bpe.model")
        if not os.path.exists(sp_path):
            raise FileNotFoundError(f"Не найден {sp_path}")
        self.sp = spm.SentencePieceProcessor(model_file=sp_path)
        self.model = ctranslate2.Translator(
            model_dir,
            device=device,
            compute_type="auto",
            intra_threads=threads,
        )
        self.languages = load_language_codes(model_dir)
        self._known = set(self.languages)
        self.name = os.path.basename(os.path.normpath(model_dir))

    def supports(self, code: str) -> bool:
        return code in self._known

    def _segments(self, line: str):
        if len(self.sp.encode(line)) <= MAX_SEGMENT_TOKENS:
            return [line]
        out = []
        for p in (p for p in SENTENCE_SPLIT.split(line) if p.strip()):
            pieces = self.sp.encode(p, out_type=str)
            # Очень длинное «предложение» без знаков препинания — режем по токенам.
            for i in range(0, len(pieces), MAX_SEGMENT_TOKENS):
                out.append(self.sp.decode(pieces[i:i + MAX_SEGMENT_TOKENS]))
        return out

    def translate(self, text: str, source: str, target: str) -> str:
        if source == target or not text.strip():
            return text

        # Сохраняем структуру строк: каждую непустую строку переводим отдельно.
        lines = text.split("\n")
        jobs = []  # (line_index, segment)
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped:
                for seg in self._segments(stripped):
                    jobs.append((i, seg))
        if not jobs:
            return text

        batch = [[source] + self.sp.encode(seg, out_type=str) + ["</s>"] for _, seg in jobs]
        results = self.model.translate_batch(
            batch,
            target_prefix=[[target]] * len(batch),
            beam_size=4,
            max_batch_size=16,
            max_decoding_length=512,
            repetition_penalty=1.1,
            no_repeat_ngram_size=4,
        )

        translated = [[] for _ in lines]
        for (i, _), res in zip(jobs, results):
            tokens = res.hypotheses[0]
            if tokens and tokens[0] == target:
                tokens = tokens[1:]
            translated[i].append(self.sp.decode(tokens))

        out_lines = []
        for line, parts in zip(lines, translated):
            if parts:
                indent = line[: len(line) - len(line.lstrip())]
                out_lines.append(indent + " ".join(parts))
            else:
                out_lines.append(line)
        return "\n".join(out_lines)


def make_handler(translator: Translator, lock: threading.Lock):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, payload: dict):
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/health":
                self._send(200, {"ready": True, "model": translator.name})
            elif self.path == "/languages":
                self._send(200, {"languages": translator.languages})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/translate":
                self._send(404, {"error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                data = json.loads(self.rfile.read(length) or b"{}")
                text = str(data.get("text", ""))
                source, target = data.get("source"), data.get("target")
                if not (translator.supports(source) and translator.supports(target)):
                    self._send(400, {"error": f"неподдерживаемый язык: {source} -> {target}"})
                    return
                with lock:
                    result = translator.translate(text, source, target)
                self._send(200, {"translation": result})
            except Exception as e:  # noqa: BLE001 — отдаём ошибку клиенту, сервер продолжает работу
                self._send(500, {"error": str(e)})

        def log_message(self, fmt, *args):
            sys.stderr.write("[server] " + (fmt % args) + "\n")

    return Handler


def default_threads() -> int:
    """На Apple Silicon используем только производительные ядра: экономичные замедляют перевод."""
    try:
        out = subprocess.run(["sysctl", "-n", "hw.perflevel0.physicalcpu"],
                             capture_output=True, text=True, timeout=2).stdout.strip()
        if out.isdigit() and int(out) > 0:
            return int(out)
    except (OSError, subprocess.SubprocessError):
        pass
    return max(1, (os.cpu_count() or 4) - 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="папка с моделью CTranslate2")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--threads", type=int, default=default_threads())
    args = ap.parse_args()

    translator = Translator(args.model, args.device, args.threads)
    # Прогрев: первый перевод всегда медленнее.
    translator.translate("Hello", "eng_Latn", "rus_Cyrl")

    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(translator, threading.Lock()))
    print(f"Sokrat server ready on 127.0.0.1:{args.port} ({translator.name}, "
          f"{len(translator.languages)} languages)", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
