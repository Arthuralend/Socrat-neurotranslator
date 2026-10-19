"""«Сократ — нейропереводчик» для Windows.

Выделите текст в любой программе и дважды нажмите Ctrl+C — появится окно с переводом.
Перевод офлайн: модель Meta NLLB-200 (CTranslate2) работает прямо на компьютере.

Запуск из исходников:  python windows/sokrat_win.py --model <папка_модели>
Самопроверка (CI):      python windows/sokrat_win.py --selftest --model <папка> --report <файл>
"""

import argparse
import logging
import os
import sys
import time
import traceback
from pathlib import Path

FROZEN = getattr(sys, "frozen", False)
if FROZEN:
    APP_DIR = Path(sys.executable).resolve().parent
    RES_DIR = Path(getattr(sys, "_MEIPASS", APP_DIR))
    FONTS_DIR = RES_DIR / "Fonts"
    ICON_PATH = RES_DIR / "assets" / "sokrat.ico"
    DEFAULT_MODEL = APP_DIR / "model"
else:
    ROOT = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(ROOT / "server"))
    FONTS_DIR = ROOT / "app" / "Resources" / "Fonts"
    ICON_PATH = ROOT / "windows" / "assets" / "sokrat.ico"
    DEFAULT_MODEL = Path(os.environ.get("SOKRAT_MODEL", ROOT / "model"))

sys.path.insert(0, str(Path(__file__).resolve().parent))
import languages  # noqa: E402

from PySide6.QtCore import (QObject, QPoint, QPointF, QRectF, QSettings, QThread, QTimer,  # noqa: E402
                            QUrl, Qt, Signal, Slot, QLockFile, QDir)
from PySide6.QtGui import (QAction, QColor, QCursor, QDesktopServices, QFont, QFontDatabase,  # noqa: E402
                           QGuiApplication, QIcon, QKeySequence, QPainter, QPainterPath, QPalette,
                           QPen, QPixmap, QShortcut)
from PySide6.QtWidgets import (QApplication, QFrame, QGraphicsDropShadowEffect, QHBoxLayout,  # noqa: E402
                               QLabel, QLineEdit, QListWidget, QListWidgetItem, QMenu,
                               QPlainTextEdit, QPushButton, QSizePolicy, QSystemTrayIcon,
                               QVBoxLayout, QWidget)

log = logging.getLogger("sokrat")

DEVELOPER_EMAIL = "armenoid@gmail.com"
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
CARD_W, CARD_H, SHADOW = 680, 470, 24

ARMENIAN_FAMILY = "Noto Serif Armenian Black"

QSS = """
* { font-family: "Manrope"; }
#card { background: #FFFFFF; border-radius: 24px; }
QLabel { color: #1E1530; background: transparent; }
#title { font-size: 17px; font-weight: 800; }
#subtitle, #hints, #langSub, #count { color: #6B6280; font-size: 12px; }
#chip { background: #F3EEFF; color: #5B21B6; border-radius: 13px; padding: 0 12px; font-size: 12px; font-weight: 700; }
#close { background: #F4F2F8; color: #4B4360; border: none; border-radius: 15px; font-size: 12px; font-weight: 800; }
#close:hover { background: #E9E4F3; }
#swap { background: #FFFFFF; color: #7C3AED; border: 2px solid #DDD6FE; border-radius: 22px; font-size: 17px; font-weight: 800; }
#swap:hover { border-color: #7C3AED; }
#lang { background: #F7F5FC; border: 2px solid #F7F5FC; border-radius: 16px; text-align: left; }
#lang:hover { border-color: #DDD6FE; }
#lang[highlighted="true"] { background: #FFFFFF; border: 2px solid #7C3AED; }
#langCode { color: #7C3AED; font-size: 22px; font-weight: 800; }
#langName { font-size: 14px; font-weight: 700; }
#chevron { color: #A39BB8; font-size: 11px; }
#sourceCard { background: #F7F5FC; border-radius: 18px; }
#source { background: transparent; border: none; color: #3B3350; font-size: 15px;
          selection-background-color: #DDD6FE; selection-color: #1E1530; }
#resultCard { background: #6D28D9; border-radius: 18px; }
#result { background: transparent; border: none; color: #FFFFFF; font-size: 16px; font-weight: 500;
          selection-background-color: #A78BFA; selection-color: #FFFFFF; }
#caption { color: #DDD6FE; font-size: 12px; }
#copy { background: #FFFFFF; color: #5B21B6; border: none; border-radius: 10px; padding: 0 14px;
        font-size: 13px; font-weight: 800; }
#copy:disabled { color: #B9A6F0; }
#popup { background: #FFFFFF; border: 1px solid #DDD6FE; border-radius: 12px; }
#popup QLineEdit { border: 1px solid #DDD6FE; border-radius: 8px; padding: 6px 8px; font-size: 13px; }
#popup QListWidget { border: none; font-size: 13px; outline: 0; }
#popup QListWidget::item { padding: 5px 6px; border-radius: 6px; color: #1E1530; }
#popup QListWidget::item:selected, #popup QListWidget::item:hover { background: #F3EEFF; color: #1E1530; }
QScrollBar:vertical { width: 8px; background: transparent; }
QScrollBar::handle:vertical { background: rgba(127, 110, 170, 0.35); border-radius: 4px; min-height: 24px; }
QScrollBar::add-line, QScrollBar::sub-line { height: 0; }
"""


def ru_plural(n, one, few, many):
    n10, n100 = n % 10, n % 100
    if n10 == 1 and n100 != 11:
        return one
    if 2 <= n10 <= 4 and not 12 <= n100 <= 14:
        return few
    return many


def load_fonts():
    global ARMENIAN_FAMILY
    loaded = []
    for f in sorted(FONTS_DIR.glob("*.ttf")):
        fid = QFontDatabase.addApplicationFont(str(f))
        families = QFontDatabase.applicationFontFamilies(fid) if fid >= 0 else []
        loaded += families
        if f.name.startswith("NotoSerifArmenian") and families:
            ARMENIAN_FAMILY = families[0]
    return loaded


def logo_pixmap(size, dpr=2.0):
    pm = QPixmap(int(size * dpr), int(size * dpr))
    pm.setDevicePixelRatio(dpr)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
    path = QPainterPath()
    path.addRoundedRect(QRectF(0, 0, size, size), size * 0.3, size * 0.3)
    p.fillPath(path, QColor("#7C3AED"))
    font = QFont(ARMENIAN_FAMILY)
    font.setPixelSize(int(size * 0.62))
    p.setFont(font)
    p.setPen(QColor("#FFFFFF"))
    p.drawText(QRectF(0, size * 0.04, size, size), Qt.AlignCenter, "Թ")
    d = size * 0.15
    p.setPen(Qt.NoPen)
    p.setBrush(QColor("#FDE68A"))
    p.drawEllipse(QRectF(size - size * 0.12 - d, size * 0.12, d, d))
    p.end()
    return pm


# ---- Движок перевода (в отдельном потоке) -------------------------------------

class Engine(QObject):
    ready = Signal(list)
    load_failed = Signal(str)
    done = Signal(int, str, float)
    failed = Signal(int, str)

    def __init__(self, model_dir):
        super().__init__()
        self.model_dir = Path(model_dir)
        self.translator = None
        self.latest = 0  # номер последнего запроса; устаревшие пропускаем

    @Slot()
    def load(self):
        try:
            from translate_server import Translator, default_threads
            self.translator = Translator(str(self.model_dir), "cpu", default_threads())
            self.translator.translate("Hello", "eng_Latn", "rus_Cyrl")  # прогрев
            self.ready.emit(list(self.translator.languages))
        except Exception as e:  # noqa: BLE001
            log.exception("model load failed")
            self.load_failed.emit(str(e))

    @Slot(int, str, str, str)
    def translate(self, req, text, source, target):
        if req < self.latest:
            return
        if self.translator is None:
            self.failed.emit(req, "Модель ещё загружается")
            return
        started = time.perf_counter()
        try:
            out = self.translator.translate(text, source, target)
        except Exception as e:  # noqa: BLE001
            log.exception("translate failed")
            self.failed.emit(req, str(e))
            return
        self.done.emit(req, out, time.perf_counter() - started)


# ---- Элементы интерфейса ------------------------------------------------------

class DragHeader(QWidget):
    """Шапка, за которую можно перетаскивать окно без рамки."""

    def mousePressEvent(self, e):
        if e.button() == Qt.LeftButton:
            self._offset = e.globalPosition().toPoint() - self.window().frameGeometry().topLeft()

    def mouseMoveEvent(self, e):
        if e.buttons() & Qt.LeftButton and hasattr(self, "_offset"):
            self.window().move(e.globalPosition().toPoint() - self._offset)


class LangPopup(QFrame):
    """Список ~200 языков с поиском; избранные — сверху."""

    def __init__(self, on_pick, allow_auto, selected, available):
        super().__init__(None, Qt.Popup | Qt.FramelessWindowHint)
        self.setObjectName("popup")
        self.on_pick, self.allow_auto, self.selected, self.available = on_pick, allow_auto, selected, available
        self.setFixedSize(300, 380)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(10, 10, 10, 10)
        lay.setSpacing(6)
        self.search = QLineEdit(placeholderText="Поиск языка")
        self.list = QListWidget()
        lay.addWidget(self.search)
        lay.addWidget(self.list)
        self.search.textChanged.connect(self.fill)
        self.search.returnPressed.connect(self.pick_first)
        self.list.itemClicked.connect(self.pick)
        self.fill("")
        self.search.setFocus()

    def _header(self, text):
        item = QListWidgetItem(text.upper())
        item.setFlags(Qt.NoItemFlags)
        f = QFont("Manrope")
        f.setPixelSize(11)
        f.setBold(True)
        item.setFont(f)
        item.setForeground(QColor("#6B6280"))
        self.list.addItem(item)

    def _row(self, code, name):
        item = QListWidgetItem(("✓  " if code == self.selected else "     ") + name)
        item.setData(Qt.UserRole, code or "")
        self.list.addItem(item)

    def fill(self, query):
        self.list.clear()
        q = query.strip().lower()
        if not q:
            if self.allow_auto:
                self._row(None, "Определить автоматически")
            self._header("Избранные")
            for code in languages.FAVORITES:
                self._row(code, languages.NAMES[code])
            self._header("Все языки")
        else:
            self._header("Найдено")
        for code, name in languages.all_sorted(self.available):
            if not q or q in name.lower() or q in code.lower():
                self._row(code, name)

    def pick_first(self):
        for i in range(self.list.count()):
            item = self.list.item(i)
            if item.flags() & Qt.ItemIsEnabled:
                self.pick(item)
                return

    def pick(self, item):
        code = item.data(Qt.UserRole)
        self.close()
        self.on_pick(code or None)


class LangButton(QPushButton):
    def __init__(self, subtitle, highlighted=False):
        super().__init__()
        self.setObjectName("lang")
        self.setProperty("highlighted", "true" if highlighted else "false")
        self.setFixedHeight(58)
        self.setCursor(Qt.PointingHandCursor)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        lay = QHBoxLayout(self)
        lay.setContentsMargins(16, 0, 16, 0)
        lay.setSpacing(12)
        self.code = QLabel("··", objectName="langCode")
        self.code.setMinimumWidth(36)
        col = QVBoxLayout()
        col.setSpacing(0)
        self.name = QLabel("", objectName="langName")
        self.sub = QLabel(subtitle, objectName="langSub")
        col.addStretch()
        col.addWidget(self.name)
        col.addWidget(self.sub)
        col.addStretch()
        chevron = QLabel("▼", objectName="chevron")
        lay.addWidget(self.code)
        lay.addLayout(col, 1)
        lay.addWidget(chevron)
        for w in (self.code, self.name, self.sub, chevron):
            w.setAttribute(Qt.WA_TransparentForMouseEvents)

    def show_lang(self, code, subtitle=None):
        self.code.setText(languages.short_code(code) if code else "··")
        self.name.setText(languages.NAMES.get(code, "Определить язык") if code else "Определить язык")
        if subtitle is not None:
            self.sub.setText(subtitle)


class ResultCard(QFrame):
    """Фиолетовая карточка перевода с тонкой орбитой и «спутником» в углу."""

    def paintEvent(self, e):
        super().paintEvent(e)
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        clip = QPainterPath()
        clip.addRoundedRect(QRectF(self.rect()), 18, 18)
        p.setClipPath(clip)
        p.translate(self.width() - 30, 6)
        p.rotate(-14)
        p.setPen(QPen(QColor(255, 255, 255, 41), 2))
        p.setBrush(Qt.NoBrush)
        p.drawEllipse(QPointF(0, 0), 100, 34)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor("#FDE68A"))
        p.drawEllipse(QPointF(-86.6, -17.0), 5, 5)
        p.end()


class TranslatorWindow(QWidget):
    request = Signal(int, str, str, str)

    def __init__(self, settings, engine=None):
        super().__init__(None, Qt.FramelessWindowHint | Qt.Tool | Qt.WindowStaysOnTopHint)
        self.settings = settings
        self.engine = engine
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setFixedSize(CARD_W + 2 * SHADOW, CARD_H + 2 * SHADOW)
        self.setWindowTitle("Сократ")

        self.source_lang = None      # None — автоопределение
        self.detected = None
        self.target = self.primary()
        self.target_chosen = False
        self.available = None
        self.ready = False
        self.req = 0
        self.prev_hwnd = None

        self._build()
        self.debounce = QTimer(self, singleShot=True, interval=350, timeout=self.translate_now)
        if engine is not None:
            self.request.connect(engine.translate)
            engine.done.connect(self.on_done)
            engine.failed.connect(self.on_failed)

        QShortcut(QKeySequence(Qt.Key_Escape), self, activated=self.hide_window)
        QShortcut(QKeySequence("Ctrl+W"), self, activated=self.hide_window)
        QShortcut(QKeySequence("Ctrl+Return"), self, activated=self.copy_result)
        QShortcut(QKeySequence("Ctrl+Enter"), self, activated=self.copy_result)

    # настройки направлений
    def primary(self):
        return self.settings.value("primaryTarget", "rus_Cyrl")

    def secondary(self):
        return self.settings.value("secondaryTarget", "eng_Latn")

    def _build(self):
        outer = QVBoxLayout(self)
        outer.setContentsMargins(SHADOW, SHADOW, SHADOW, SHADOW)
        card = QFrame(objectName="card")
        shadow = QGraphicsDropShadowEffect(card, blurRadius=48, offset=QPointF(0, 14))
        shadow.setColor(QColor(46, 16, 101, 70))
        card.setGraphicsEffect(shadow)
        outer.addWidget(card)

        lay = QVBoxLayout(card)
        lay.setContentsMargins(18, 18, 18, 14)
        lay.setSpacing(14)

        # шапка
        header = DragHeader()
        h = QHBoxLayout(header)
        h.setContentsMargins(4, 0, 4, 0)
        h.setSpacing(12)
        logo = QLabel()
        logo.setPixmap(logo_pixmap(40))
        titles = QVBoxLayout()
        titles.setSpacing(0)
        titles.addWidget(QLabel("Сократ", objectName="title"))
        titles.addWidget(QLabel("нейропереводчик · 200 языков", objectName="subtitle"))
        self.chip = QLabel("●  Загрузка…", objectName="chip")
        self.chip.setFixedHeight(26)
        self.chip.setAlignment(Qt.AlignCenter)
        close = QPushButton("✕", objectName="close")
        close.setFixedSize(30, 30)
        close.setCursor(Qt.PointingHandCursor)
        close.setToolTip("Закрыть (Esc)")
        close.clicked.connect(self.hide_window)
        h.addWidget(logo)
        h.addLayout(titles, 1)
        h.addWidget(self.chip)
        h.addWidget(close)
        lay.addWidget(header)

        # языки
        row = QHBoxLayout()
        row.setSpacing(10)
        self.src_btn = LangButton("определён автоматически")
        self.src_btn.clicked.connect(lambda: self.open_popup(self.src_btn, True, self.source_lang, self.pick_source))
        swap = QPushButton("⇄", objectName="swap")
        swap.setFixedSize(44, 44)
        swap.setCursor(Qt.PointingHandCursor)
        swap.setToolTip("Поменять языки местами")
        swap.clicked.connect(self.swap)
        self.dst_btn = LangButton("перевод на", highlighted=True)
        self.dst_btn.clicked.connect(lambda: self.open_popup(self.dst_btn, False, self.target, self.pick_target))
        row.addWidget(self.src_btn, 1)
        row.addWidget(swap)
        row.addWidget(self.dst_btn, 1)
        lay.addLayout(row)

        # карточки
        cards = QHBoxLayout()
        cards.setSpacing(10)
        src_card = QFrame(objectName="sourceCard")
        sc = QVBoxLayout(src_card)
        sc.setContentsMargins(12, 10, 12, 12)
        sc.setSpacing(6)
        self.source = QPlainTextEdit(objectName="source")
        self.source.setPlaceholderText("Вставьте или введите текст")
        self.source.textChanged.connect(self.on_source_changed)
        self.count = QLabel("0 символов", objectName="count")
        sc.addWidget(self.source, 1)
        sc.addWidget(self.count)

        res_card = ResultCard(objectName="resultCard")
        rc = QVBoxLayout(res_card)
        rc.setContentsMargins(14, 12, 16, 14)
        rc.setSpacing(10)
        self.result = QPlainTextEdit(objectName="result")
        self.result.setReadOnly(True)
        self.result.setPlaceholderText("Перевод появится здесь")
        bottom = QHBoxLayout()
        self.caption = QLabel("", objectName="caption")
        self.caption.setWordWrap(True)
        self.copy_btn = QPushButton("Копировать  Ctrl+↵", objectName="copy")
        self.copy_btn.setFixedHeight(34)
        self.copy_btn.setCursor(Qt.PointingHandCursor)
        self.copy_btn.setEnabled(False)
        self.copy_btn.clicked.connect(self.copy_result)
        bottom.addWidget(self.caption, 1)
        bottom.addWidget(self.copy_btn)
        rc.addWidget(self.result, 1)
        rc.addLayout(bottom)

        cards.addWidget(src_card, 1)
        cards.addWidget(res_card, 1)
        lay.addLayout(cards, 1)

        hints = QLabel("Ctrl+C Ctrl+C — перевести выделенное   ·   Ctrl+A, Ctrl+C, Ctrl+V работают   ·   Esc — закрыть",
                       objectName="hints")
        hints.setAlignment(Qt.AlignCenter)
        lay.addWidget(hints)

        # полупрозрачный белый текст-подсказка на фиолетовой карточке
        pal = self.result.palette()
        pal.setColor(QPalette.ColorRole.PlaceholderText, QColor(255, 255, 255, 150))
        self.result.setPalette(pal)
        self.refresh_langs()

    # ---- состояние ----
    def effective_source(self):
        return self.source_lang or self.detected

    def refresh_langs(self):
        self.src_btn.show_lang(self.effective_source(),
                               "определён автоматически" if self.source_lang is None else "язык текста")
        self.dst_btn.show_lang(self.target)

    def auto_pick_target(self):
        self.detected = languages.detect(self.source.toPlainText())
        if not self.target_chosen:
            src = self.effective_source()
            self.target = self.secondary() if src == self.primary() else self.primary()
        self.refresh_langs()

    def set_ready(self, available):
        self.ready = True
        self.available = set(available) if available else None
        self.chip.setText("●  Офлайн")

    def set_load_error(self, message):
        self.chip.setText("●  Ошибка")
        self.caption.setText("Модель не загрузилась: " + message)

    def load_text(self, text):
        self.source_lang = None
        self.target_chosen = False
        self.result.setPlainText("")
        self.caption.setText("")
        self.source.blockSignals(True)
        self.source.setPlainText(text)
        self.source.blockSignals(False)
        self.on_source_changed()
        self.debounce.start(0)

    def on_source_changed(self):
        n = len(self.source.toPlainText())
        self.count.setText(f"{n} {ru_plural(n, 'символ', 'символа', 'символов')}")
        self.auto_pick_target()
        self.debounce.start()

    def translate_now(self):
        text = self.source.toPlainText()
        self.req += 1
        if self.engine is not None:
            self.engine.latest = self.req
        if not text.strip():
            self.result.setPlainText("")
            self.caption.setText("")
            self.copy_btn.setEnabled(False)
            return
        src = self.effective_source()
        if src is None:
            self.caption.setText("Не удалось определить язык — выберите его вручную")
            return
        if src == self.target:
            self.result.setPlainText(text)
            self.copy_btn.setEnabled(True)
            self.caption.setText("")
            return
        self.caption.setText("переводим…" if self.ready else "Загружается модель перевода…")
        self.request.emit(self.req, text, src, self.target)

    @Slot(int, str, float)
    def on_done(self, req, text, seconds):
        if req != self.req:
            return
        self.result.setPlainText(text)
        self.copy_btn.setEnabled(bool(text))
        self.caption.setText(f"перевод за {seconds:.1f} с".replace(".", ","))

    @Slot(int, str)
    def on_failed(self, req, message):
        if req == self.req:
            self.caption.setText("Ошибка: " + message)

    # ---- действия ----
    def open_popup(self, button, allow_auto, selected, on_pick):
        popup = LangPopup(on_pick, allow_auto, selected, self.available)
        popup.setStyleSheet(QSS)
        popup.move(button.mapToGlobal(QPoint(0, button.height() + 6)))
        popup.show()
        self._popup = popup

    def pick_source(self, code):
        self.source_lang = code
        self.auto_pick_target()
        self.debounce.start(0)

    def pick_target(self, code):
        if code:
            self.target = code
            self.target_chosen = True
            self.refresh_langs()
            self.debounce.start(0)

    def swap(self):
        src = self.effective_source()
        if not src:
            return
        old_target = self.target
        self.target_chosen = True
        self.target = src
        self.source_lang = old_target
        translated = self.result.toPlainText()
        if translated:
            self.source.blockSignals(True)
            self.source.setPlainText(translated)
            self.source.blockSignals(False)
        self.on_source_changed()

    def copy_result(self):
        text = self.result.toPlainText()
        if text:
            QGuiApplication.clipboard().setText(text)
            self.caption.setText("скопировано")

    def show_near_cursor(self, text, prev_hwnd=None):
        self.prev_hwnd = prev_hwnd
        self.load_text(text)
        if not self.isVisible():
            pos = QCursor.pos()
            screen = QGuiApplication.screenAt(pos) or QGuiApplication.primaryScreen()
            area = screen.availableGeometry()
            x = min(max(pos.x() + 12 - SHADOW, area.left()), area.right() - self.width())
            y = min(max(pos.y() + 12 - SHADOW, area.top()), area.bottom() - self.height())
            self.move(x, y)
        self.show()
        self.raise_()
        self.activateWindow()
        if sys.platform == "win32":
            import winkeys
            winkeys.bring_to_front(int(self.winId()))
        self.source.setFocus()

    def hide_window(self):
        self.hide()
        if sys.platform == "win32" and self.prev_hwnd:
            import winkeys
            winkeys.restore_focus(self.prev_hwnd)


# ---- Приложение в трее --------------------------------------------------------

def autostart_enabled():
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, "Sokrat")
            return True
    except OSError:
        return False


def set_autostart(enabled):
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
        if enabled:
            winreg.SetValueEx(k, "Sokrat", 0, winreg.REG_SZ, f'"{sys.executable}"')
        else:
            try:
                winreg.DeleteValue(k, "Sokrat")
            except OSError:
                pass


class TrayApp(QObject):
    triggered = Signal(object)  # hwnd окна, из которого копировали

    def __init__(self, app, model_dir, log_path):
        super().__init__()
        self.app = app
        self.log_path = log_path
        self.settings = QSettings("LuSoft", "Sokrat")

        self.thread = QThread()
        self.engine = Engine(model_dir)
        self.engine.moveToThread(self.thread)
        self.thread.started.connect(self.engine.load)
        self.engine.ready.connect(self.on_ready)
        self.engine.load_failed.connect(self.on_load_failed)
        self.thread.start()

        self.window = TranslatorWindow(self.settings, self.engine)
        self.window.setStyleSheet(QSS)

        self.tray = QSystemTrayIcon(QIcon(str(ICON_PATH)), self)
        self.tray.setToolTip("Сократ — двойное Ctrl+C для перевода")
        self.tray.activated.connect(self.on_tray_click)
        self.build_menu()
        self.tray.show()

        self.triggered.connect(self.on_double_copy)
        self.hook = None
        if sys.platform == "win32":
            import winkeys
            self.hook = winkeys.DoubleCopyHook(lambda: self.triggered.emit(winkeys.foreground_window()))
            self.hook.start()
            # Хук переустанавливаем раз в 10 минут: Windows может молча снять его.
            self.rehook = QTimer(self, interval=10 * 60 * 1000, timeout=self.hook.restart)
            self.rehook.start()

        if not self.settings.value("welcomed", False, type=bool):
            self.settings.setValue("welcomed", True)
            self.tray.showMessage("Сократ работает", "Выделите текст в любой программе и дважды нажмите Ctrl+C.",
                                  QIcon(str(ICON_PATH)), 6000)

    def build_menu(self):
        menu = QMenu()
        menu.addAction("Перевести буфер обмена", self.translate_clipboard)
        menu.addSeparator()
        self._lang_menu(menu, "Переводить на", "primaryTarget", "rus_Cyrl")
        self._lang_menu(menu, "Если текст уже на нём — на", "secondaryTarget", "eng_Latn")
        menu.addSeparator()
        auto = QAction("Запускать при входе в Windows", menu, checkable=True)
        auto.setChecked(autostart_enabled() if sys.platform == "win32" else False)
        auto.toggled.connect(set_autostart)
        menu.addAction(auto)
        menu.addAction("Открыть журнал", lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.log_path))))
        menu.addSeparator()
        menu.addAction("О программе «Сократ»", self.about)
        menu.addAction("Разработчик: LuSoft — написать", self.write_developer)
        menu.addSeparator()
        menu.addAction("Выйти", self.quit)
        self.menu = menu
        self.tray.setContextMenu(menu)

    def _lang_menu(self, parent, title, key, default):
        current = self.settings.value(key, default)
        sub = parent.addMenu(f"{title}: {languages.NAMES.get(current, current)}")

        def add(menu, code):
            act = QAction(languages.NAMES[code], menu, checkable=True)
            act.setChecked(code == current)
            act.triggered.connect(lambda _=False, c=code: self.set_direction(key, c))
            menu.addAction(act)

        for code in languages.FAVORITES:
            add(sub, code)
        sub.addSeparator()
        everything = sub.addMenu("Все языки")
        for code, _ in languages.all_sorted(self.window.available):
            add(everything, code)

    def set_direction(self, key, code):
        other = "secondaryTarget" if key == "primaryTarget" else "primaryTarget"
        if self.settings.value(other, "eng_Latn" if other == "secondaryTarget" else "rus_Cyrl") == code:
            self.settings.setValue(other, self.settings.value(key, "rus_Cyrl" if key == "primaryTarget" else "eng_Latn"))
        self.settings.setValue(key, code)
        self.build_menu()

    def on_ready(self, available):
        self.window.set_ready(available)
        self.build_menu()

    def on_load_failed(self, message):
        self.window.set_load_error(message)
        self.tray.showMessage("Сократ", "Не удалось загрузить модель перевода. Подробности — в журнале.",
                              QSystemTrayIcon.Warning, 8000)

    def on_tray_click(self, reason):
        if reason == QSystemTrayIcon.Trigger:
            self.translate_clipboard()

    @Slot(object)
    def on_double_copy(self, hwnd):
        if self.window.isVisible() and self.window.isActiveWindow():
            return  # Ctrl+C Ctrl+C внутри самого окна перевода
        # Даём программе время положить текст в буфер обмена.
        QTimer.singleShot(150, lambda: self.translate_clipboard(hwnd))

    def translate_clipboard(self, prev_hwnd=None):
        text = QGuiApplication.clipboard().text()
        self.window.show_near_cursor(text, prev_hwnd)

    def about(self):
        self.tray.showMessage("Сократ — нейропереводчик",
                              f"Офлайн-перевод на модели Meta NLLB-200.\nРазработчик: LuSoft · {DEVELOPER_EMAIL}",
                              QIcon(str(ICON_PATH)), 8000)

    def write_developer(self):
        QDesktopServices.openUrl(QUrl(f"mailto:{DEVELOPER_EMAIL}?subject=Сократ — нейропереводчик"))

    def quit(self):
        if self.hook:
            self.hook.stop()
        self.thread.quit()
        self.thread.wait(2000)
        self.app.quit()


# ---- Точка входа ---------------------------------------------------------------

def setup_logging():
    base = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Sokrat"
    base.mkdir(parents=True, exist_ok=True)
    path = base / "sokrat.log"
    logging.basicConfig(filename=path, level=logging.INFO, encoding="utf-8",
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    return path


def selftest(model_dir, report):
    """Проверка без экрана: модель, определение языка, окно, хук. Пишет отчёт и снимок окна."""
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    lines, code = [], 0
    try:
        app = QApplication(sys.argv)
        fonts = load_fonts()
        lines.append(f"Шрифты: {fonts}")
        assert any("Manrope" in f for f in fonts), "шрифт Manrope не загрузился"

        from translate_server import Translator
        t = Translator(str(model_dir), "cpu", 4)
        lines.append(f"Языков в модели: {len(t.languages)}")
        for src, dst, text in [("eng_Latn", "rus_Cyrl", "Select text and press Ctrl+C twice."),
                               ("rus_Cyrl", "hye_Armn", "Привет! Как дела?"),
                               ("hye_Armn", "deu_Latn", "Այսօր եղանակը լավ է։")]:
            out = t.translate(text, src, dst)
            lines.append(f"{src} -> {dst}: {text} => {out}")
            assert out.strip() and out != text

        for text, expected in [("Բարև, ինչպե՞ս ես։", "hye_Armn"), ("Привет, как у тебя дела сегодня?", "rus_Cyrl"),
                               ("Hello, how are you doing today?", "eng_Latn"),
                               ("Bonjour, comment allez-vous aujourd'hui ?", "fra_Latn")]:
            got = languages.detect(text)
            lines.append(f"detect({text!r}) = {got}")
            assert got == expected, f"ожидалось {expected}"

        settings = QSettings(str(Path(report).with_suffix(".ini")), QSettings.IniFormat)
        w = TranslatorWindow(settings)
        w.setStyleSheet(QSS)
        w.set_ready(t.languages)
        w.load_text("The unexamined life is not worth living. Select any text, press Ctrl+C twice.")
        app.processEvents()
        w.on_done(w.req, t.translate(w.source.toPlainText(), "eng_Latn", "rus_Cyrl"), 0.6)
        w.show()
        app.processEvents()
        shot = str(Path(report).with_suffix(".png"))
        w.grab().save(shot)
        lines.append(f"Снимок окна: {shot}")

        if sys.platform == "win32":
            import winkeys
            hook = winkeys.DoubleCopyHook(lambda: None)
            hook.start()
            time.sleep(0.5)
            hook.stop()
            lines.append("Хук клавиатуры: установлен и снят")
        lines.append("OK")
    except Exception:  # noqa: BLE001
        lines.append(traceback.format_exc())
        code = 1
    Path(report).write_text("\n".join(lines), encoding="utf-8")
    return code


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=str(DEFAULT_MODEL))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--report", default="selftest.txt")
    args = ap.parse_args()

    if args.selftest:
        # os._exit: без разбора объектов Qt при выходе — отчёт уже записан.
        os._exit(selftest(args.model, args.report))

    log_path = setup_logging()
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Сократ")

    lock = QLockFile(QDir.temp().filePath("sokrat-translator.lock"))
    if not lock.tryLock(100):
        return  # уже запущен

    load_fonts()
    app.setFont(QFont("Manrope", 10))
    if not QSystemTrayIcon.isSystemTrayAvailable():
        log.warning("system tray is not available")
    _tray = TrayApp(app, args.model, log_path)  # noqa: F841 — держим ссылку до выхода
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
