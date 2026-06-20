import SwiftUI

// MARK: - Klio glass auth components

private let authInk = Color(hex: 0x2B2545)
private let authSoft = Color(hex: 0x474264)
private let authPlaceholder = Color(hex: 0x6A6490)
private let authAccent = Color(hex: 0x8A7BFF)
private func authGrad() -> LinearGradient {
    LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct KlioAuthHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                FlameMark(size: 36)
                Text("Klio").font(.system(size: 30, weight: .heavy)).foregroundStyle(authInk)
            }
            VStack(spacing: 5) {
                Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(authInk).multilineTextAlignment(.center)
                Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(authSoft)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct KlioAuthTabs: View {
    enum Tab { case login, register }
    let active: Tab
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tab("Вход", active == .login) { if active == .register { onSwitch() } }
            tab("Регистрация", active == .register) { if active == .login { onSwitch() } }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
    }

    private func tab(_ title: LocalizedStringKey, _ isActive: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .bold))
                .foregroundStyle(isActive ? .white : authSoft)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(Group { if isActive { Capsule().fill(authGrad()) } })
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
    }
}

struct KlioAuthField: View {
    let icon: String
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    var tint: Int = 0
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var showText = false
    private var color: Color { tint == 3 ? Color(hex: 0xB07ED8) : authAccent }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.16))
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            .frame(width: 42, height: 42)

            Group {
                if isSecure && !showText {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(authPlaceholder))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(authPlaceholder))
                        .keyboardType(keyboardType).autocapitalization(.none).disableAutocorrection(true)
                }
            }
            .focused($focused).submitLabel(submitLabel).onSubmit(onSubmit)
            .font(.system(size: 15, weight: .medium)).foregroundStyle(authInk).tint(color)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSecure && !text.isEmpty {
                Button { showText.toggle() } label: {
                    Image(systemName: showText ? "eye.slash" : "eye").font(.system(size: 14)).foregroundStyle(authSoft)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(focused ? color.opacity(0.7) : .white.opacity(0.5), lineWidth: focused ? 1.8 : 1))
        .shadow(color: Color(hex: 0x785AA0).opacity(focused ? 0.2 : 0.1), radius: focused ? 12 : 8, y: 5)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

struct KlioAuthPrimary: View {
    let title: LocalizedStringKey
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.white) }
                else {
                    Text(title).font(.system(size: 16, weight: .heavy))
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(isEnabled ? .white : authSoft)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(authGrad()) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(isEnabled ? nil : RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: isEnabled ? authAccent.opacity(0.4) : .clear, radius: 14, y: 7)
        }
        .buttonStyle(KlioPress(scale: 0.97))
        .disabled(isLoading || !isEnabled)
        .animation(.easeInOut(duration: 0.25), value: isEnabled)
    }
}

struct KlioSocialButton: View {
    let title: LocalizedStringKey
    var systemIcon: String? = nil
    var letterIcon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let systemIcon { Image(systemName: systemIcon).font(.system(size: 17, weight: .medium)) }
                else if let letterIcon { Text(letterIcon).font(.system(size: 17, weight: .heavy)) }
                Text(title).font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(authInk).frame(maxWidth: .infinity).frame(height: 50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1))
            .shadow(color: Color(hex: 0x785AA0).opacity(0.1), radius: 8, y: 4)
        }
        .buttonStyle(KlioPress(scale: 0.97))
    }
}

struct KlioAuthDivider: View {
    let text: LocalizedStringKey
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(authSoft.opacity(0.2)).frame(height: 1)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(authSoft).fixedSize()
            Rectangle().fill(authSoft.opacity(0.2)).frame(height: 1)
        }
    }
}

struct KlioAuthError: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Color(hex: 0xCB5A4A))
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}
// MARK: - Login

struct LoginView: View {
    var showRegister: () -> Void

    @EnvironmentObject var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            KlioMeshBg()
                .onTapGesture { UIApplication.shared.dismissKeyboard() }

            VStack(spacing: 0) {
                KlioAuthHeader(title: "С возвращением", subtitle: "продолжай свой путь")
                    .padding(.top, 56).padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        KlioAuthTabs(active: .login, onSwitch: showRegister)
                            .padding(.top, 4)

                        VStack(spacing: 12) {
                            KlioAuthField(icon: "envelope.fill", placeholder: "your@email.com",
                                          text: $email, keyboardType: .emailAddress, tint: 0)
                            KlioAuthField(icon: "lock.fill", placeholder: "пароль",
                                          text: $password, isSecure: true, tint: 3,
                                          submitLabel: .go,
                                          onSubmit: { if canSubmit { Task { await login() } } })
                        }

                        HStack {
                            Spacer()
                            Button("Забыли пароль?") { }
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(authSoft)
                        }
                        .padding(.top, 4)

                        if let error { KlioAuthError(text: error) }

                        KlioAuthPrimary(title: "Войти", isLoading: isLoading, isEnabled: canSubmit) {
                            Task { await login() }
                        }
                        .padding(.top, 10)

                        KlioAuthDivider(text: "или войти через").padding(.top, 18)

                        HStack(spacing: 10) {
                            KlioSocialButton(title: "Apple", systemIcon: "apple.logo") {
                                Task { await signInWithApple() }
                            }
                            KlioSocialButton(title: "Google", letterIcon: "G") {
                                Task { await signInWithGoogle() }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: error)
    }

    private func login() async {
        isLoading = true
        error = nil
        do {
            struct Body: Encodable { let email: String; let password: String }
            let resp: TokenResponse = try await APIClient.shared.request(
                "auth/login", method: "POST", body: Body(email: email, password: password)
            )
            await session.logIn(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
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
            // тихо игнорируем отмену
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
            // тихо игнорируем отмену
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
