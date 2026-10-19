import AppKit
import ApplicationServices

/// Ловит двойное нажатие ⌘C в любом приложении.
/// Требует разрешения «Универсальный доступ» (Accessibility).
final class DoubleCopyMonitor {
    var onTrigger: (() -> Void)?

    private var monitor: Any?
    private var lastPress: TimeInterval = 0
    private let maxInterval: TimeInterval = 0.5
    private var trustTimer: Timer?

    private static let keyC: UInt16 = 8  // kVK_ANSI_C — та же физическая клавиша в русской раскладке (С)

    static var isTrusted: Bool { AXIsProcessTrusted() }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            install()
        } else {
            // Ждём, пока пользователь выдаст разрешение, затем ставим монитор без перезапуска.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard AXIsProcessTrusted() else { return }
                t.invalidate()
                self?.install()
            }
        }
    }

    private func install() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == Self.keyC, !event.isARepeat else { return }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods == .command else {
            lastPress = 0
            return
        }
        if event.timestamp - lastPress < maxInterval {
            lastPress = 0
            onTrigger?()
        } else {
            lastPress = event.timestamp
        }
    }
}
