import AppKit

@main
@MainActor
enum SokratApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // только значок в строке меню, без Dock
        app.run()
    }
}
