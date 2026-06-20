import SwiftUI

struct RegisterView: View {
    var showLogin: () -> Void

    @EnvironmentObject var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    private var canSubmit: Bool { !email.isEmpty && password.count >= 6 }

    var body: some View {
        ZStack(alignment: .top) {
            KlioMeshBg()
                .onTapGesture { UIApplication.shared.dismissKeyboard() }

            VStack(spacing: 0) {
                KlioAuthHeader(title: "Добро пожаловать", subtitle: "начни свой путь сегодня")
                    .padding(.top, 56).padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        KlioAuthTabs(active: .register, onSwitch: showLogin)
                            .padding(.top, 4)

                        VStack(spacing: 12) {
                            KlioAuthField(icon: "envelope.fill", placeholder: "your@email.com",
                                          text: $email, keyboardType: .emailAddress, tint: 0)
                            KlioAuthField(icon: "lock.fill", placeholder: "минимум 6 символов",
                                          text: $password, isSecure: true, tint: 3)
                        }

                        if let error { KlioAuthError(text: error) }

                        KlioAuthPrimary(title: "Создать аккаунт", isLoading: isLoading, isEnabled: canSubmit) {
                            Task { await register() }
                        }
                        .padding(.top, 2)

                        KlioAuthDivider(text: "или войти через").padding(.top, 6)

                        HStack(spacing: 10) {
                            KlioSocialButton(title: "Apple", systemIcon: "apple.logo") {
                                Task { await signInWithApple() }
                            }
                            KlioSocialButton(title: "Google", letterIcon: "G") {
                                Task { await signInWithGoogle() }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Язык приложения").font(.system(size: 11, weight: .heavy)).tracking(1.2)
                                .foregroundStyle(Color(hex: 0x474264)).padding(.leading, 4)
                            LanguagePicker()
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: error)
    }

    private func register() async {
        isLoading = true
        error = nil
        do {
            struct Body: Encodable { let email: String; let password: String }
            let resp: TokenResponse = try await APIClient.shared.request(
                "auth/register", method: "POST", body: Body(email: email, password: password)
            )
            session.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func signInWithApple() async {
        error = nil
        isLoading = true
        do {
            try await SocialAuth.signInWithApple(session: session)
        } catch let e as SocialAuthError where e.isCancellation {
            // молча игнорируем отмену
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func signInWithGoogle() async {
        error = nil
        isLoading = true
        do {
            try await SocialAuth.signInWithGoogle(session: session)
        } catch let e as SocialAuthError where e.isCancellation {
            // молча игнорируем отмену
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
