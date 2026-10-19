"""Проверяет, что модель загружается и переводит. Используется в CI."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "server"))
from translate_server import Translator  # noqa: E402

t = Translator(sys.argv[1], "cpu", 4)
print(f"Языков в модели: {len(t.languages)}")
cases = [
    ("eng_Latn", "rus_Cyrl", "The weather is nice today, let's go for a walk."),
    ("rus_Cyrl", "hye_Armn", "Сегодня хорошая погода."),
    ("hye_Armn", "deu_Latn", "Այսօր եղանակը լավ է։"),
    ("fra_Latn", "por_Latn", "Je voudrais un café, s'il vous plaît."),
    ("spa_Latn", "jpn_Jpan", "¿Dónde está la estación de tren?"),
    ("eng_Latn", "rus_Cyrl", "First line.\n\nSecond paragraph after an empty line."),
]
for src, dst, text in cases:
    out = t.translate(text, src, dst)
    print(f"  {src} -> {dst}: {text!r}\n      => {out!r}")
    assert out.strip() and out != text, "пустой или непереведённый результат"
assert t.translate("a\n\nb", "eng_Latn", "rus_Cyrl").count("\n") == 2, "потеряны переносы строк"
print("OK")
