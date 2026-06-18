import SwiftUI

struct AuthFlow: View {
    @State private var showRegister = false

    var body: some View {
        ZStack {
            if showRegister {
                RegisterView(showLogin: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showRegister = false
                    }
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .trailing))
                ))
            } else {
                LoginView(showRegister: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showRegister = true
                    }
                })
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
            }
        }
    }
}
