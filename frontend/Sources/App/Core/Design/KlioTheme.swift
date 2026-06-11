import SwiftUI

// MARK: - Klio design system
// Светлый, чистый, в духе Apple Fitness/Health: яркие градиентные кольца —
// герой, крупные округлые цифры, цвет живёт в мягких градиентах.

enum Klio {
    // v3: тёплый песок + изумруд, глубина. Поверхности
    static let bg       = Color(hex: 0xF6F1E9)   // тёплый песочный фон
    static let surface  = Color(hex: 0xFFFDFA)   // тёплая белая карточка
    static let sunken   = Color(hex: 0xEEE8DF)   // треки/утопленное
    static let hair     = Color(hex: 0xE7E0D4)   // тонкие границы

    // Текст
    static let ink      = Color(hex: 0x211C17)
    static let inkSoft  = Color(hex: 0xA89C8C)
    static let inkFaint = Color(hex: 0xC4BAA9)

    // Сигнатурный акцент (изумруд → зелёный) + семантика
    static let accent   = Color(hex: 0x2FB6A3)
    static let accent2  = Color(hex: 0x3FA06B)
    static let done     = Color(hex: 0x3FA06B)   // «сделано»
    static let over     = Color(hex: 0xD98A3D)   // «превышение» (янтарь)

    // Тёмная герой-карточка
    static let heroDark1 = Color(hex: 0x1F2A28)
    static let heroDark2 = Color(hex: 0x2C3C36)
    static let onDark     = Color(hex: 0xEAF1EE)
    static let onDarkSoft = Color(hex: 0x9FB4AD)
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [heroDark1, heroDark2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Единый акцент (совместимость со старым API gradColors/tint).
    static func gradColors(_ i: Int) -> [Color] { [accent, accent2] }
    static func tint(_ i: Int) -> Color { accent }
    static func gradient(_ i: Int) -> LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Метрики
    static let radius: CGFloat = 24
    static let radiusSmall: CGFloat = 16
    static let pad: CGFloat = 18
}

// MARK: - Color hex

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Typography (округлый «приборный» характер)

extension Font {
    static func klioNumber(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func klioTitle(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func klioText(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func klioCaps(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold)
    }
}

// MARK: - Card primitive

struct KlioCard<Content: View>: View {
    var padding: CGFloat = Klio.pad
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Klio.surface)
            .clipShape(RoundedRectangle(cornerRadius: Klio.radius, style: .continuous))
            .shadow(color: Klio.ink.opacity(0.05), radius: 12, y: 5)
    }
}

// MARK: - Gradient ring (герой)

struct KlioRing<Content: View>: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 10
    var track: Color = Klio.sunken
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.0001, min(progress, 1)))
                .stroke(
                    AngularGradient(gradient: Gradient(colors: colors + [colors.first ?? .clear]),
                                    center: .center,
                                    startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)
            content
        }
    }
}

// MARK: - Caps label

struct KlioCaps: View {
    let text: String
    var color: Color = Klio.inkFaint
    var body: some View {
        Text(text.uppercased()).font(.klioCaps()).tracking(1.3).foregroundStyle(color)
    }
}

// MARK: - Haptics

enum Haptic {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        Task { @MainActor in UIImpactFeedbackGenerator(style: style).impactOccurred() }
    }
}

// MARK: - Press feedback button style

struct KlioPress: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Keyboard dismiss (app-wide)

extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
