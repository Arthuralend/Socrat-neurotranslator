import Foundation

/// Запускает встроенный в приложение Python-сервер перевода и перезапускает его при падении.
final class ServerManager {
    static let shared = ServerManager()

    private var process: Process?
    private var stopping = false
    private let baseURL = URL(string: "http://127.0.0.1:\(Settings.port)")!

    private var resources: URL { Bundle.main.resourceURL! }
    private var pythonURL: URL { resources.appendingPathComponent("python/bin/python3") }
    private var modelURL: URL { resources.appendingPathComponent("model") }
    private var scriptURL: URL { resources.appendingPathComponent("translate_server.py") }

    var logURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sokrat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("server.log")
    }

    func start() {
        stopping = false
        Task {
            if !(await isReady()) {
                await MainActor.run { self.launch() }
                guard await waitUntilReady() else { return }
            }
            await loadLanguages()
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }

    func isReady() async -> Bool {
        guard let json = await get("health", timeout: 1) else { return false }
        return json["ready"] as? Bool == true
    }

    /// Ждёт готовности сервера (загрузка модели занимает несколько секунд).
    func waitUntilReady(timeout: TimeInterval = 120) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isReady() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private func loadLanguages() async {
        guard let codes = await get("languages", timeout: 5)?["languages"] as? [String] else { return }
        await MainActor.run { Lang.restrict(to: Set(codes)) }
    }

    private func get(_ path: String, timeout: TimeInterval) async -> [String: Any]? {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.timeoutInterval = timeout
        guard let data = try? await URLSession.shared.data(for: req).0 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func launch() {
        // Приложение не подписано Apple, поэтому macOS помечает скачанные файлы «карантином».
        // Снимаем его со встроенного Python, иначе система может заблокировать его запуск.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", resources.appendingPathComponent("python").path]
        if (try? xattr.run()) != nil { xattr.waitUntilExit() }

        let p = Process()
        p.executableURL = pythonURL
        // -I: изолированный режим, -B: не писать .pyc внутрь подписанного приложения
        p.arguments = ["-I", "-B", scriptURL.path, "--model", modelURL.path, "--port", String(Settings.port)]

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let log = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = log
            p.standardError = log
        }
        p.terminationHandler = { [weak self] _ in
            guard let self, !self.stopping else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.launch() }
        }
        do {
            try p.run()
            process = p
        } catch {
            NSLog("Sokrat: failed to start server: \(error)")
        }
    }

    func translate(_ text: String, from source: Lang, to target: Lang) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("translate"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "source": source.code, "target": target.code,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let t = json["translation"] as? String { return t }
        throw NSError(domain: "Sokrat", code: 1, userInfo: [
            NSLocalizedDescriptionKey: json["error"] as? String ?? "Неизвестная ошибка сервера",
        ])
    }
}
