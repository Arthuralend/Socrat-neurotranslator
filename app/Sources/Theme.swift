import AppKit
import SwiftUI

/// Цвета и шрифты фиолетового дизайна «Сократа».
/// Шрифты лежат в Contents/Resources/Fonts и подключаются через ATSApplicationFontsPath в Info.plist.
enum Theme {
    static let violet = Color(hex: 0x7C3AED)
    static let violetDeep = Color(hex: 0x6D28D9)
    static let violetDark = Color(hex: 0x5B21B6)
    static let lavender = Color(hex: 0xF3EEFF)
    static let lavenderBorder = Color(hex: 0xDDD6FE)
    static let surface = Color(hex: 0xF7F5FC)
    static let closeBackground = Color(hex: 0xF4F2F8)
    static let ink = Color(hex: 0x1E1530)
    static let inkSoft = Color(hex: 0x3B3350)
    static let muted = Color(hex: 0x6B6280)
    static let faint = Color(hex: 0xA39BB8)
    static let star = Color(hex: 0xFDE68A)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Manrope-Medium"
        case .semibold: name = "Manrope-SemiBold"
        case .bold: name = "Manrope-Bold"
        case .heavy, .black: name = "Manrope-ExtraBold"
        default: name = "Manrope-Regular"
        }
        return .custom(name, size: size)
    }

    static func armenian(_ size: CGFloat) -> Font {
        .custom("NotoSerifArmenian-Black", size: size)
    }

    /// Значок для строки меню: буква Թ в круге со «спутником».
    /// Шаблонное изображение — macOS сама красит его под светлую или тёмную тему.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            let ring = NSRect(x: 1.5, y: 1.5, width: 15, height: 15)
            let path = NSBezierPath(ovalIn: ring)
            path.lineWidth = 1.4
            NSColor.black.setStroke()
            path.stroke()

            let font = NSFont(name: "NotoSerifArmenian-Black", size: 10.5) ?? .boldSystemFont(ofSize: 10)
            let glyph = NSAttributedString(string: "Թ", attributes: [.font: font, .foregroundColor: NSColor.black])
            let ink = glyph.boundingRect(with: .zero, options: [.usesDeviceMetrics])
            glyph.draw(at: NSPoint(x: ring.midX - ink.width / 2 - ink.minX,
                                   y: ring.midY - ink.height / 2 - ink.minY))

            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14.6, y: 12.8, width: 4.6, height: 4.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Логотип: Թ на фиолетовом фоне с жёлтым «спутником».
struct LogoMark: View {
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.violet)
            Text("Թ")
                .font(Theme.armenian(size * 0.62))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: size * 0.04)
            Circle().fill(Theme.star)
                .frame(width: size * 0.15, height: size * 0.15)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

/// Позволяет перетаскивать окно без рамки за шапку.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Русское склонение: 1 символ, 2 символа, 5 символов.
func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n10 = n % 10, n100 = n % 100
    if n10 == 1 && n100 != 11 { return one }
    if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
    return many
}
