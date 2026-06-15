import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @State private var minTimePassed = false

    private var showSplash: Bool { session.isBootstrapping || !minTimePassed }

    var body: some View {
        mainBody
    }

    private var mainBody: some View {
        ZStack {
            Group {
                if ProcessInfo.processInfo.environment["KLIO_ONB"] == "1" {
                    OnboardingFlow()
                } else if session.isLoggedIn {
                    if session.onboardingComplete {
                        KlioTabRoot()
                    } else {
                        OnboardingFlow()
                    }
                } else {
                    AuthFlow()
                }
            }
            .animation(.easeInOut, value: session.isLoggedIn)

            if showSplash {
                KlioSplash()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.45), value: showSplash)
        .task {
            // минимум, чтобы анимация успела проиграться, а не мелькнула
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            minTimePassed = true
        }
    }
}
