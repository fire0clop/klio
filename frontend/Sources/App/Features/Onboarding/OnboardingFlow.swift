import SwiftUI

private let obInk = Color(hex: 0x2B2545)
private let obSoft = Color(hex: 0x474264)
private let obFaint = Color(hex: 0x726C92)
private let obAccent = Color(hex: 0x8A7BFF)
private func obGrad() -> LinearGradient {
    LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct OnboardingFlow: View {
    /// Called when the user taps the cancel / back button. Pass `nil` to logout.
    var onCancel: (() -> Void)? = nil

    @EnvironmentObject var session: SessionStore

    @State private var step = Int(ProcessInfo.processInfo.environment["KLIO_ONB_STEP"] ?? "") ?? 0
    @State private var name = ProcessInfo.processInfo.environment["KLIO_ONB"] == "1" ? "Егор" : ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var gender = "male"
    @State private var heightCm = ""
    @State private var weightKg = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            KlioMeshBg()
                .onTapGesture { UIApplication.shared.dismissKeyboard() }
            VStack(spacing: 0) {
                topBar
                if step == 0 { stepOne } else { stepTwo }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack {
                Button { leftAction() } label: {
                    Image(systemName: step == 0 ? "xmark" : "chevron.left")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(obSoft)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
                Spacer()
                Text(LocalizedStringKey(step == 0 ? "О себе" : "Параметры тела"))
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(obInk)
                Spacer()
                if step == 1 {
                    Button { Task { await save() } } label: {
                        Text("Пропустить").font(.system(size: 13, weight: .bold)).foregroundStyle(obAccent)
                    }
                    .disabled(isLoading)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? AnyShapeStyle(obGrad()) : AnyShapeStyle(Color(hex: 0x786EAA).opacity(0.14)))
                        .frame(height: 5)
                        .animation(.spring(response: 0.4), value: step)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }

    private func leftAction() {
        if step == 1 { withAnimation(.spring(response: 0.35)) { step = 0 } }
        else if let onCancel { onCancel() } else { session.logout() }
    }

    // MARK: - Step 1

    private var stepOne: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    hero(icon: "person.fill", title: "Расскажи о себе",
                         subtitle: "Это поможет персонализировать\nотслеживание для тебя")

                    glassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Имя", "person.fill")
                            TextField("Как тебя зовут?", text: $name)
                                .font(.system(size: 16, weight: .medium)).foregroundStyle(obInk).tint(obAccent).submitLabel(.done)
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            label("Дата рождения", "calendar")
                            DatePicker("", selection: $dateOfBirth,
                                       in: ...Calendar.current.date(byAdding: .year, value: -5, to: Date())!,
                                       displayedComponents: .date)
                                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                                .environment(\.locale, LocaleManager.shared.locale)
                                .tint(obAccent)
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(obAccent)
                                Text(String(format: L("Возраст: %lld лет"), computedAge)).font(.system(size: 12, weight: .semibold)).foregroundStyle(obSoft)
                            }
                        }
                    }

                    glassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            label("Пол", "figure.stand")
                            HStack(spacing: 8) {
                                ForEach([("male", "Мужской"), ("female", "Женский"), ("other", "Другой")], id: \.0) { tag, l in
                                    genderButton(tag: tag, label: l)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)

            bottomButton(title: "Далее", disabled: name.isEmpty) {
                withAnimation(.spring(response: 0.35)) { step = 1 }
            }
        }
    }

    private func genderButton(tag: String, label: String) -> some View {
        let selected = gender == tag
        return Button { withAnimation(.spring(response: 0.25)) { gender = tag } } label: {
            Text(LocalizedStringKey(label)).font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? .white : obInk)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(
                    selected
                        ? AnyShapeStyle(obGrad())
                        : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(selected ? nil : RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(obAccent.opacity(0.25), lineWidth: 1.2))
        }
        .buttonStyle(KlioPress(scale: 0.97))
    }

    // MARK: - Step 2

    private var stepTwo: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    hero(icon: "figure.run", title: "Параметры тела",
                         subtitle: "Необязательно, но помогает\nточнее отслеживать прогресс")

                    glassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Рост, см", "ruler")
                            TextField("", text: $heightCm, prompt: Text("180").foregroundColor(obFaint))
                                .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(obInk).tint(obAccent).keyboardType(.decimalPad)
                        }
                    }
                    glassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Вес, кг", "scalemass.fill")
                            TextField("", text: $weightKg, prompt: Text("75").foregroundColor(obFaint))
                                .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(obInk).tint(obAccent).keyboardType(.decimalPad)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(obFaint)
                        Text("Ты всегда сможешь изменить данные в профиле")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(obFaint)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)

            bottomButton(title: "Начать", disabled: isLoading) { Task { await save() } }
        }
    }

    // MARK: - Shared

    private func hero(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: 0x8A7BFF).opacity(0.16)).frame(width: 88, height: 88).blur(radius: 14)
                Circle().fill(obGrad()).frame(width: 74, height: 74)
                    .shadow(color: Color(hex: 0x8A7BFF).opacity(0.4), radius: 15, y: 7)
                Image(systemName: icon).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.top, 16)
            Text(LocalizedStringKey(title)).font(.system(size: 22, weight: .heavy)).foregroundStyle(obInk)
            Text(LocalizedStringKey(subtitle)).font(.system(size: 14, weight: .medium)).foregroundStyle(obSoft).multilineTextAlignment(.center)
        }
    }

    private func glassCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1))
            .shadow(color: Color(hex: 0x785AA0).opacity(0.1), radius: 10, y: 4)
    }

    private func label(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(obAccent)
            Text(L(text).uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(obSoft)
        }
    }

    private func bottomButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else { Text(LocalizedStringKey(title)).font(.system(size: 16, weight: .heavy)) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(disabled && !isLoading ? obFaint.opacity(0.8) : .white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(disabled && !isLoading ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(obGrad()))
            )
            .overlay(disabled && !isLoading ? RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1) : nil)
            .shadow(color: disabled ? .clear : obAccent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(KlioPress(scale: 0.97))
        .disabled(disabled)
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var computedAge: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }

    private func save() async {
        isLoading = true
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        struct Body: Encodable {
            var name: String?; var dateOfBirth: String?; var gender: String?
            var heightCm: Double?; var weightKg: Double?; var language: String; var onboardingCompleted: Bool
        }
        let body = Body(
            name: name.isEmpty ? nil : name,
            dateOfBirth: formatter.string(from: dateOfBirth),
            gender: gender,
            heightCm: Double(heightCm.replacingOccurrences(of: ",", with: ".")),
            weightKg: Double(weightKg.replacingOccurrences(of: ",", with: ".")),
            language: LocaleManager.shared.language.rawValue,
            onboardingCompleted: true
        )
        _ = try? await APIClient.shared.request(
            "profile", method: "PUT", body: body, token: session.token
        ) as ProfileResponse
        session.markOnboardingComplete()
        isLoading = false
    }
}
