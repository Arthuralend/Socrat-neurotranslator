import AppKit
import Combine
import SwiftUI

@MainActor
final class TranslatorViewModel: ObservableObject {
    @Published var sourceText = ""
    @Published var sourceLang: Lang?  // nil = автоопределение
    @Published var targetLang: Lang = Settings.primaryTarget
    @Published private(set) var detectedLang: Lang?
    @Published private(set) var result = ""
    @Published private(set) var status = ""
    @Published private(set) var isBusy = false
    @Published private(set) var serverReady = false
    @Published private(set) var lastDuration: TimeInterval?

    private var targetChosenByUser = false
    private var task: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    init() {
        Publishers.CombineLatest3($sourceText, $sourceLang, $targetLang)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.translate() }
            .store(in: &bag)
    }

    var effectiveSource: Lang? { sourceLang ?? detectedLang }

    func load(_ text: String) {
        targetChosenByUser = false
        sourceLang = nil
        result = ""
        lastDuration = nil
        sourceText = text
        autoPickTarget()
        Task { serverReady = await ServerManager.shared.isReady() }
    }

    func userPickedTarget(_ lang: Lang) {
        targetChosenByUser = true
        targetLang = lang
    }

    func swap() {
        guard let src = effectiveSource else { return }
        let oldTarget = targetLang
        targetChosenByUser = true
        if !result.isEmpty { sourceText = result }
        sourceLang = oldTarget
        targetLang = src
    }

    func copyResult() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    private func autoPickTarget() {
        detectedLang = LanguageDetector.detect(sourceText)
        guard !targetChosenByUser else { return }
        let t = Settings.target(for: effectiveSource)
        if t != targetLang { targetLang = t }
    }

    private func translate() {
        autoPickTarget()
        task?.cancel()
        isBusy = false
        let text = sourceText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = ""; status = ""; return
        }
        guard let src = effectiveSource else {
            status = "Не удалось определить язык — выберите его вручную"; return
        }
        let tgt = targetLang
        if src == tgt { result = text; status = ""; return }

        isBusy = true
        status = ""
        task = Task {
            defer { if !Task.isCancelled { isBusy = false } }
            if !(await ServerManager.shared.isReady()) {
                status = "Загружается модель перевода…"
                guard await ServerManager.shared.waitUntilReady() else {
                    status = "Сервер перевода не запустился. Лог: ~/Library/Logs/Sokrat/server.log"
                    return
                }
                status = ""
            }
            serverReady = true
            let started = Date()
            do {
                let out = try await ServerManager.shared.translate(text, from: src, to: tgt)
                guard !Task.isCancelled else { return }
                result = out
                lastDuration = Date().timeIntervalSince(started)
            } catch {
                guard !Task.isCancelled else { return }
                status = "Ошибка: \(error.localizedDescription)"
            }
        }
    }
}

/// Выбор языка из ~200 с поиском по названию; избранные языки — сверху.
struct LanguagePicker: View {
    let selection: Lang?      // выбранный язык (nil — автоопределение)
    let shown: Lang?          // что показать на кнопке (при «авто» — найденный язык)
    let subtitle: String
    var allowAuto = false
    var highlighted = false
    let onPick: (Lang?) -> Void

    @State private var isOpen = false
    @State private var query = ""

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 12) {
                Text(shown?.shortCode ?? "··")
                    .font(Theme.font(22, .heavy))
                    .foregroundColor(Theme.violet)
                    .frame(minWidth: 34, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shown?.name ?? "Определить язык")
                        .font(Theme.font(14, .bold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.font(11.5))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.faint)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlighted ? Color.white : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(highlighted ? Theme.violet : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                TextField("Поиск языка", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.font(13))
                List {
                    if query.isEmpty {
                        if allowAuto { row(nil, "Определить автоматически") }
                        Section(header: Text("Избранные").font(Theme.font(11, .bold))) {
                            ForEach(Lang.favorites) { row($0, $0.name) }
                        }
                    }
                    Section(header: Text(query.isEmpty ? "Все языки" : "Найдено").font(Theme.font(11, .bold))) {
                        ForEach(Lang.all.filter { $0.matches(query) }) { row($0, $0.name) }
                    }
                }
            }
            .padding(10)
            .frame(width: 280, height: 380)
        }
    }

    private func row(_ lang: Lang?, _ title: String) -> some View {
        Button {
            onPick(lang)
            isOpen = false
            query = ""
        } label: {
            HStack {
                Text(title).font(Theme.font(13, .medium))
                Spacer()
                if lang == selection {
                    Image(systemName: "checkmark").foregroundColor(Theme.violet)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Тонкая орбита со «спутником» в углу карточки перевода.
struct OrbitDecoration: View {
    var body: some View {
        ZStack {
            Ellipse()
                .stroke(Color.white.opacity(0.16), lineWidth: 2)
                .frame(width: 200, height: 68)
                .rotationEffect(.degrees(-14))
            Circle().fill(Theme.star)
                .frame(width: 10, height: 10)
                .offset(x: 86, y: -16)
        }
        .frame(width: 220, height: 120)
    }
}

struct TranslatorView: View {
    @ObservedObject var model: TranslatorViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            header
            languageRow
            HStack(spacing: 10) {
                sourceCard
                resultCard
            }
            hints
        }
        .padding(18)
        .frame(width: PanelMetrics.size.width, height: PanelMetrics.size.height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            LogoMark(size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Сократ").font(Theme.font(17, .heavy)).foregroundColor(Theme.ink)
                Text("нейропереводчик · 200 языков").font(Theme.font(12)).foregroundColor(Theme.muted)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(model.serverReady ? Theme.violet : Theme.faint).frame(width: 7, height: 7)
                Text(model.serverReady ? "Офлайн" : "Загрузка…")
                    .font(Theme.font(12, .bold))
                    .foregroundColor(Theme.violetDark)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.lavender))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: 0x4B4360))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.closeBackground))
            }
            .buttonStyle(.plain)
            .help("Закрыть (Esc)")
        }
        .padding(.horizontal, 4)
        .background(WindowDragArea())
    }

    private var languageRow: some View {
        HStack(spacing: 10) {
            LanguagePicker(
                selection: model.sourceLang,
                shown: model.effectiveSource,
                subtitle: model.sourceLang == nil ? "определён автоматически" : "язык текста",
                allowAuto: true
            ) { model.sourceLang = $0 }

            Button(action: model.swap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.violet)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().strokeBorder(Theme.lavenderBorder, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .help("Поменять языки местами")

            LanguagePicker(
                selection: model.targetLang,
                shown: model.targetLang,
                subtitle: "перевод на",
                highlighted: true
            ) { if let lang = $0 { model.userPickedTarget(lang) } }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.sourceText)
                .font(Theme.font(14.5))
                .foregroundColor(Theme.inkSoft)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            let n = model.sourceText.count
            Text("\(n) \(ruPlural(n, "символ", "символа", "символов"))")
                .font(Theme.font(11.5))
                .foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
    }

    private var resultCard: some View {
        ZStack(alignment: .topTrailing) {
            OrbitDecoration()
                .offset(x: 96, y: -62)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(model.result.isEmpty ? "Перевод появится здесь" : model.result)
                        .font(Theme.font(15.5, .medium))
                        .foregroundColor(.white.opacity(model.result.isEmpty ? 0.6 : 1))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    if model.isBusy {
                        ProgressView().controlSize(.small).colorScheme(.dark)
                    }
                    Text(resultCaption)
                        .font(Theme.font(11.5))
                        .foregroundColor(Theme.lavenderBorder)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button(action: model.copyResult) {
                        Text("Копировать ⌘↩")
                            .font(Theme.font(12.5, .heavy))
                            .foregroundColor(Theme.violetDark)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.result.isEmpty)
                    .opacity(model.result.isEmpty ? 0.6 : 1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.violetDeep)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultCaption: String {
        if !model.status.isEmpty { return model.status }
        if model.isBusy { return "переводим…" }
        if let d = model.lastDuration {
            return "перевод за " + String(format: "%.1f", d).replacingOccurrences(of: ".", with: ",") + " с"
        }
        return ""
    }

    private var hints: some View {
        HStack(spacing: 14) {
            Text("⌘C ⌘C — перевести выделенное")
            Text("·")
            Text("⌘A, ⌘C, ⌘V работают")
            Text("·")
            Text("Esc — закрыть")
        }
        .font(Theme.font(11.5))
        .foregroundColor(Theme.muted)
        .frame(maxWidth: .infinity)
    }
}

/// Окно без рамки: скругления и тень рисует сам интерфейс.
final class TranslatorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

enum PanelMetrics {
    static let size = NSSize(width: 680, height: 470)
}

@MainActor
final class TranslatorPanelController {

    private let model = TranslatorViewModel()
    private var keyMonitor: Any?

    private lazy var panel: TranslatorPanel = {
        let p = TranslatorPanel(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.size),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.appearance = NSAppearance(named: .aqua)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: TranslatorView(model: self.model) { [weak self] in self?.hide() })
        return p
    }()

    init() {
        // Esc и ⌘W закрывают окно, даже когда курсор в поле ввода.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 53 || (event.keyCode == 13 && mods == .command) {
                self.hide()
                return nil
            }
            return event
        }
    }

    func show(text: String) {
        model.load(text)
        if !panel.isVisible { position(near: NSEvent.mouseLocation) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
        NSApp.hide(nil)  // вернуть фокус приложению, из которого переводили
    }

    private func position(near point: NSPoint) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: point.x + 12, y: point.y - size.height - 12)
        origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - size.width - 8)
        origin.y = min(max(origin.y, vis.minY + 8), vis.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}
