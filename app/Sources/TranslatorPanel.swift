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
        sourceText = text
        autoPickTarget()
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
            do {
                let out = try await ServerManager.shared.translate(text, from: src, to: tgt)
                guard !Task.isCancelled else { return }
                result = out
            } catch {
                guard !Task.isCancelled else { return }
                status = "Ошибка: \(error.localizedDescription)"
            }
        }
    }
}

/// Выбор языка из ~200 с поиском по названию; избранные языки — сверху.
struct LanguagePicker: View {
    let selection: Lang?
    var autoTitle: String?  // если задано — первым пунктом идёт «Определить язык»
    let onPick: (Lang?) -> Void

    @State private var shown = false
    @State private var query = ""

    var body: some View {
        Button { shown.toggle() } label: {
            HStack {
                Text(selection?.name ?? autoTitle ?? "—").lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                TextField("Поиск языка", text: $query)
                    .textFieldStyle(.roundedBorder)
                List {
                    if query.isEmpty {
                        if let autoTitle { row(nil, autoTitle) }
                        Section(header: Text("Избранные")) {
                            ForEach(Lang.favorites) { row($0, $0.name) }
                        }
                    }
                    Section(header: Text(query.isEmpty ? "Все языки" : "Найдено")) {
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
            shown = false
            query = ""
        } label: {
            HStack {
                Text(title)
                Spacer()
                if lang == selection { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TranslatorView: View {
    @ObservedObject var model: TranslatorViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                LanguagePicker(selection: model.sourceLang, autoTitle: autoLabel) { model.sourceLang = $0 }

                Button(action: model.swap) { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless)
                    .help("Поменять языки местами")

                LanguagePicker(selection: model.targetLang) { if let l = $0 { model.userPickedTarget(l) } }
            }

            TextEditor(text: $model.sourceText)
                .font(.system(size: 13))
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

            ZStack(alignment: .topLeading) {
                ScrollView {
                    Text(model.result)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                if model.isBusy && model.result.isEmpty {
                    ProgressView().controlSize(.small).padding(8)
                }
            }
            .frame(minHeight: 90)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                if model.isBusy && !model.result.isEmpty { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).foregroundColor(.secondary).lineLimit(2)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.result, forType: .string)
                } label: { Label("Копировать", systemImage: "doc.on.doc") }
                    .disabled(model.result.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Закрыть", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(minWidth: 440, minHeight: 260)
    }

    private var autoLabel: String {
        if let d = model.detectedLang { return "Авто: \(d.name)" }
        return "Определить язык"
    }
}

/// Плавающее окно-панель, появляется у курсора поверх всех окон.
final class TranslatorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class TranslatorPanelController {
    private let model = TranslatorViewModel()
    private lazy var panel: TranslatorPanel = {
        let p = TranslatorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        p.title = "Сократ"
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: TranslatorView(model: self.model) { [weak p] in p?.orderOut(nil) })
        return p
    }()

    func show(text: String) {
        model.load(text)
        if !panel.isVisible { position(near: NSEvent.mouseLocation) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
