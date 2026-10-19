import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = DoubleCopyMonitor()
    private let panel = TranslatorPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ServerManager.shared.start()
        setupStatusItem()

        monitor.onTrigger = { [weak self] in
            // Даём второму ⌘C время положить текст в буфер обмена.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.translateClipboard() }
        }
        monitor.start()

        // Автозапуск при входе в систему — включаем один раз при первом старте.
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ServerManager.shared.stop()
    }

    @objc private func translateClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        panel.show(text: text)
    }

    // MARK: - Строка меню

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Σ"
        statusItem.button?.toolTip = "Сократ — двойное ⌘C для перевода"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item("Перевести буфер обмена", #selector(translateClipboard), key: ""))
        menu.addItem(.separator())

        menu.addItem(languageSubmenu("Переводить на", current: Settings.primaryTarget, action: #selector(setPrimary(_:))))
        menu.addItem(languageSubmenu("Если текст уже на нём — на", current: Settings.secondaryTarget,
                                     action: #selector(setSecondary(_:))))
        menu.addItem(.separator())

        let login = item("Запускать при входе в систему", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(item("Настройки «Универсального доступа»…", #selector(openAccessibility)))
        menu.addItem(item("Открыть лог сервера", #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(item("Выйти", #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func languageSubmenu(_ title: String, current: Lang, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(current.name)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for lang in Lang.favorites { sub.addItem(languageItem(lang, current: current, action: action)) }
        sub.addItem(.separator())
        let allItem = NSMenuItem(title: "Все языки", action: nil, keyEquivalent: "")
        let all = NSMenu()
        for lang in Lang.all { all.addItem(languageItem(lang, current: current, action: action)) }
        allItem.submenu = all
        sub.addItem(allItem)
        parent.submenu = sub
        return parent
    }

    private func languageItem(_ lang: Lang, current: Lang, action: Selector) -> NSMenuItem {
        let i = item(lang.name, action)
        i.representedObject = lang.code
        i.state = lang == current ? .on : .off
        return i
    }

    @objc private func setPrimary(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, let lang = Lang.byCode(code) else { return }
        if lang == Settings.secondaryTarget { Settings.secondaryTarget = Settings.primaryTarget }
        Settings.primaryTarget = lang
        rebuildMenu()
    }

    @objc private func setSecondary(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, let lang = Lang.byCode(code) else { return }
        if lang == Settings.primaryTarget { Settings.primaryTarget = Settings.secondaryTarget }
        Settings.secondaryTarget = lang
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(ServerManager.shared.logURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
