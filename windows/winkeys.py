"""Windows: перехват двойного Ctrl+C и вывод окна на передний план.

Низкоуровневый хук клавиатуры (WH_KEYBOARD_LL) работает без прав администратора
и ничего не блокирует: нажатия проходят в программы как обычно.
"""

import ctypes
import logging
import threading
import time
from ctypes import wintypes

log = logging.getLogger("sokrat.keys")

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

WH_KEYBOARD_LL = 13
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x0100, 0x0101, 0x0104, 0x0105
WM_QUIT = 0x0012
VK_C, VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN = 0x43, 0x10, 0x11, 0x12, 0x5B, 0x5C

LRESULT = ctypes.c_ssize_t
HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD),
        ("scanCode", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_size_t),
    ]


user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
user32.SetWindowsHookExW.restype = wintypes.HHOOK
user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
user32.CallNextHookEx.restype = LRESULT
user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
user32.GetMessageW.argtypes = [ctypes.POINTER(wintypes.MSG), wintypes.HWND, wintypes.UINT, wintypes.UINT]
user32.GetMessageW.restype = wintypes.BOOL
user32.PostThreadMessageW.argtypes = [wintypes.DWORD, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.GetAsyncKeyState.restype = ctypes.c_short
user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.BringWindowToTop.argtypes = [wintypes.HWND]
user32.IsWindow.argtypes = [wintypes.HWND]
kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE


def _down(vk):
    return bool(user32.GetAsyncKeyState(vk) & 0x8000)


class DoubleCopyHook:
    """Вызывает on_trigger() (из потока хука), когда Ctrl+C нажат дважды подряд."""

    def __init__(self, on_trigger, interval=0.5):
        self.on_trigger = on_trigger
        self.interval = interval
        self._last = 0.0
        self._c_down = False
        self._thread = None
        self._thread_id = 0
        self._proc = HOOKPROC(self._callback)  # держим ссылку, иначе сборщик мусора удалит колбэк

    def start(self):
        self._thread = threading.Thread(target=self._run, name="double-ctrl-c", daemon=True)
        self._thread.start()

    def stop(self):
        if self._thread and self._thread_id:
            user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)
            self._thread.join(timeout=2)
        self._thread = None
        self._thread_id = 0

    def restart(self):
        # Windows молча снимает хук, если он однажды ответил слишком медленно; переустанавливаем его.
        self.stop()
        self.start()

    def _run(self):
        self._thread_id = kernel32.GetCurrentThreadId()
        hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, self._proc, kernel32.GetModuleHandleW(None), 0)
        if not hook:
            log.error("SetWindowsHookExW failed: %s", ctypes.get_last_error())
            return
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            pass
        user32.UnhookWindowsHookEx(hook)

    def _callback(self, n_code, w_param, l_param):
        if n_code == 0:
            kb = ctypes.cast(l_param, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
            if kb.vkCode == VK_C:
                if w_param in (WM_KEYDOWN, WM_SYSKEYDOWN):
                    if not self._c_down:  # автоповтор при удержании клавиши не считаем
                        self._c_down = True
                        self._on_ctrl_c()
                elif w_param in (WM_KEYUP, WM_SYSKEYUP):
                    self._c_down = False
        return user32.CallNextHookEx(None, n_code, w_param, l_param)

    def _on_ctrl_c(self):
        if not _down(VK_CONTROL) or any(_down(vk) for vk in (VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN)):
            self._last = 0.0
            return
        now = time.monotonic()
        if now - self._last < self.interval:
            self._last = 0.0
            try:
                self.on_trigger()
            except Exception:  # noqa: BLE001 — ошибка в интерфейсе не должна ронять хук
                log.exception("on_trigger failed")
        else:
            self._last = now


def foreground_window():
    return user32.GetForegroundWindow()


def bring_to_front(hwnd):
    """Windows не даёт фоновой программе забирать фокус; обходим через AttachThreadInput."""
    fg = user32.GetForegroundWindow()
    fg_thread = user32.GetWindowThreadProcessId(fg, None) if fg else 0
    cur = kernel32.GetCurrentThreadId()
    attached = bool(fg_thread and fg_thread != cur and user32.AttachThreadInput(fg_thread, cur, True))
    try:
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
    finally:
        if attached:
            user32.AttachThreadInput(fg_thread, cur, False)


def restore_focus(hwnd):
    if hwnd and user32.IsWindow(hwnd):
        bring_to_front(hwnd)
