import SwiftUI

struct LanguagePicker: View {
    @EnvironmentObject var locale: LocaleManager
    var onChange: ((AppLanguage) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppLanguage.allCases) { lang in
                let active = locale.language == lang
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { locale.language = lang }
                    Haptic.tap()
                    onChange?(lang)
                } label: {
                    HStack(spacing: 6) {
                        Text(lang.flag).font(.system(size: 14))
                        Text(lang.nativeName).font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(active ? .white : Color(hex: 0x474264))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(
                        active
                            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Capsule()
                    )
                    .overlay(active ? nil : Capsule().stroke(.white.opacity(0.55), lineWidth: 1))
                    .shadow(color: active ? Color(hex: 0x8A7BFF).opacity(0.3) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(KlioPress(scale: 0.96))
            }
        }
    }
}
