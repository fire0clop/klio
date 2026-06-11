import SwiftUI

@main
struct KlioApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var locale = LocaleManager.shared

    init() {
        // Точки-пагинации (TabView .page) в фирменный фиолетовый, а не блёкло-серые.
        let pc = UIPageControl.appearance()
        pc.currentPageIndicatorTintColor = UIColor(Color(hex: 0x8A7BFF))
        pc.pageIndicatorTintColor = UIColor(Color(hex: 0x8A7BFF).opacity(0.22))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(locale)
                .environment(\.locale, locale.locale)
                .id(locale.language)
        }
    }
}
