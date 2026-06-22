import SwiftUI

// MARK: - Editable fields

enum ProfileField: String, Identifiable {
    case name, dob, gender, height, weight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Имя"
        case .dob: return "Дата рождения"
        case .gender: return "Пол"
        case .height: return "Рост"
        case .weight: return "Вес"
        }
    }
    var icon: String {
        switch self {
        case .name: return "person.fill"
        case .dob: return "calendar"
        case .gender: return "figure.stand"
        case .height: return "ruler"
        case .weight: return "scalemass.fill"
        }
    }
    var tint: Int {
        switch self {
        case .name: return 0
        case .dob: return 1
        case .gender: return 2
        case .height: return 3
        case .weight: return 4
        }
    }
}

struct ProfilePatch: Encodable {
    var name: String?
    var dateOfBirth: String?
    var gender: String?
    var heightCm: Double?
    var weightKg: Double?
    var language: String?
}

// MARK: - Profile · «Твоя сфера» (glass, animated)

struct ProfileView: View {
    var showsClose: Bool = true
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ProfileResponse?
    @State private var editing: ProfileField?
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var activeGoals = 0
    @State private var bestStreak = 0
    @State private var totalDone = 0
    @State private var spheres: [SphereResponse] = []
    @State private var scrollY: CGFloat = 0
    @State private var reveal = false
    @State private var ringProgress: CGFloat = 0

    private let ink = Color(hex: 0x2B2545)
    private let soft = Color(hex: 0x4A4568)
    private let privacyURL = URL(string: "https://fire0clop.github.io/klio-legal/privacy.html")!
    private let termsURL = URL(string: "https://fire0clop.github.io/klio-legal/terms.html")!

    var body: some View {
        ZStack(alignment: .top) {
            KlioMeshBg()

            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear.preference(key: ProfileScrollKey.self, value: geo.frame(in: .named("pscroll")).minY)
                    }.frame(height: 0)

                    indexHero.padding(.top, 52)

                    if let p = profile {
                        VStack(spacing: 22) {
                            statsRow.reveal(reveal, index: 0)
                            section("ДАННЫЕ") { infoCard(p) }.reveal(reveal, index: 1)
                            section("ЯЗЫК") {
                                LanguagePicker(onChange: { lang in
                                    if !Demo.enabled { Task { await save(ProfilePatch(language: lang.rawValue)) } }
                                })
                            }.reveal(reveal, index: 2)
                            section("О ПРИЛОЖЕНИИ") { aboutCard }.reveal(reveal, index: 3)
                            section("АККАУНТ") { accountCard }.reveal(reveal, index: 4)
                        }
                        .padding(.horizontal, 16).padding(.top, 26).padding(.bottom, 130)
                    } else {
                        ProgressView().tint(Color(hex: 0x8A7BFF)).frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .klioReadable()
            }
            .coordinateSpace(name: "pscroll")
            .onPreferenceChange(ProfileScrollKey.self) { scrollY = $0 }
            .scrollIndicators(.hidden)

            closeButton
        }
        .task {
            await loadProfile(); await loadStats(); await loadSpheres()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { reveal = true }
            withAnimation(.easeOut(duration: 1.2)) { ringProgress = 1 }
        }
        .sheet(item: $editing) { field in
            ProfileFieldEditor(field: field, profile: profile) { patch in await save(patch) }
                .presentationDetents([.height(field == .dob ? 470 : 300)])
                .presentationDragIndicator(.visible)
        }
        .alert("Выйти из аккаунта?", isPresented: $showLogoutConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Выйти", role: .destructive) { dismiss(); session.logout() }
        } message: { Text("Тебе нужно будет войти снова") }
        .alert("Удалить аккаунт?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("Все твои данные, цели и история будут удалены навсегда. Это действие нельзя отменить.")
        }
        .alert("Не удалось удалить аккаунт", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Проверь соединение и попробуй ещё раз.")
        }
    }

    // MARK: Close

    @ViewBuilder
    private var closeButton: some View {
        if showsClose {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                        .frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
            }
            .padding(.horizontal, 18).padding(.top, 10)
        }
    }

    // MARK: Index hero («человек как число» — общий индекс развития)

    private var indexHero: some View {
        let pull = max(scrollY, 0)
        let nodes = Array(spheres.prefix(6))
        return VStack(spacing: 18) {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    // дышащее свечение в цвет уровня
                    Circle().fill(tierColor.opacity(0.20)).frame(width: 220, height: 220)
                        .scaleEffect(CGFloat(1 + 0.03 * sin(t * 1.3))).blur(radius: 30)
                    // трек (остаток до 100 — пунктир, чтобы читалось «сколько добрать»)
                    Circle().stroke(Color(hex: 0x8076A6).opacity(0.22),
                                    style: .init(lineWidth: 16, lineCap: .butt, dash: [2, 7]))
                        .frame(width: 188, height: 188)
                    // сегментированная дуга: каждый сегмент = вклад сферы своим цветом + «серия»
                    let ff = CGFloat(overallIndex) / 100
                    ForEach(Array(indexSegments().enumerated()), id: \.offset) { _, seg in
                        let hi = max(seg.start, min(seg.end, ringProgress * ff))
                        Circle().trim(from: seg.start, to: hi)
                            .stroke(seg.color, style: .init(lineWidth: 16, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 188, height: 188)
                    }
                    centerLabel
                }
                .frame(width: 240, height: 240)
            }
            .scaleEffect(1 + pull / 700, anchor: .center)
            .offset(y: pull * 0.1)
            .opacity(1 - min(max(-scrollY, 0) / 220, 0.7))

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xFF9ECF), Color(hex: 0x8A7BFF)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    Text(initials).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName).font(.system(size: 19, weight: .heavy)).foregroundStyle(ink).lineLimit(1)
                    Text(memberLine).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(soft)
                }
            }
            .opacity(reveal ? 1 : 0)

            if !nodes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ИЗ ЧЕГО СКЛАДЫВАЕТСЯ").font(.system(size: 10.5, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(soft).padding(.leading, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(nodes) { sp in legendChip(sp) }
                            streakChip
                        }.padding(.horizontal, 18)
                    }
                    .mask(LinearGradient(stops: [
                        .init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                }
                .opacity(reveal ? 1 : 0).padding(.top, 4)
            }
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 4) {
            Text("ИНДЕКС").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(soft)
            if spheres.isEmpty {
                Text("—").font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundStyle(ink)
            } else {
                CountUp(target: overallIndex).font(.system(size: 58, weight: .heavy, design: .rounded)).foregroundStyle(ink)
            }
            Text(tierLabel).font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 3)
                .background(tierColor, in: Capsule())
        }
    }

    // Общий индекс: 0.7·среднее по сферам + 0.3·консистентность (лучшая серия / 30 дней).
    private var overallIndex: Int {
        let s = spheres.map { Double($0.percent) }
        let meanS = s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count)
        let streakScore = min(Double(bestStreak) / 30.0, 1.0) * 100
        let blended = s.isEmpty ? streakScore : 0.7 * meanS + 0.3 * streakScore
        return Int(blended.rounded())
    }
    // Сегменты кольца: каждая сфера своим цветом (доля = 0.7), хвост — «серия» (0.3).
    private func indexSegments() -> [(color: Color, start: CGFloat, end: CGFloat)] {
        let total = max(spheres.map { Double($0.percent) }.reduce(0, +), 1)
        let ff = Double(overallIndex) / 100
        let sphereFill = 0.7 * ff, streakFill = 0.3 * ff
        var out: [(Color, CGFloat, CGFloat)] = []
        var cum = 0.0
        for sp in spheres {
            let frac = sphereFill * Double(sp.percent) / total
            out.append((sphereStyle(sp.icon).color, CGFloat(cum), CGFloat(cum + frac)))
            cum += frac
        }
        out.append((Color(hex: 0xFFC36B), CGFloat(cum), CGFloat(cum + streakFill)))
        return out
    }
    private var tierColor: Color {
        switch overallIndex {
        case ..<34: return Color(hex: 0x8AA0E0)
        case 34..<67: return Color(hex: 0xB07ED8)
        default: return Color(hex: 0x4FB89A)
        }
    }
    private var tierLabel: String {
        switch overallIndex {
        case ..<34: return L("НАБИРАЕШЬ")
        case 34..<67: return L("В БАЛАНСЕ")
        default: return L("НА ПОДЪЁМЕ")
        }
    }

    private func legendChip(_ sp: SphereResponse) -> some View {
        let st = sphereStyle(sp.icon)
        return HStack(spacing: 7) {
            Image(systemName: st.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(st.color)
            Text(sp.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ink).lineLimit(1).fixedSize()
            Text("\(sp.percent)%").font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundStyle(st.color)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(st.color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(st.color.opacity(0.32), lineWidth: 1))
    }

    private var streakChip: some View {
        let c = Color(hex: 0xE8A35C)
        return HStack(spacing: 7) {
            Image(systemName: "flame.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(c)
            Text("Серия").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ink).lineLimit(1).fixedSize()
            Text("\(bestStreak)д").font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundStyle(c)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(c.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(c.opacity(0.32), lineWidth: 1))
    }


    // MARK: Stats

    private var statsRow: some View {
        VStack(spacing: 12) {
            streakAccentTile
            HStack(spacing: 12) {
                smallStat(activeGoals, "активных целей", "target", Color(hex: 0x8A7BFF))
                smallStat(totalDone, "выполнено всего", "checkmark.seal.fill", Color(hex: 0x4FA293))
            }
        }
    }

    private var streakAccentTile: some View {
        let c = Color(hex: 0xE8A35C)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.opacity(0.16)).frame(width: 50, height: 50)
                Image(systemName: "flame.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(c)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUp(target: bestStreak).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                    Text("дней").font(.system(size: 14, weight: .bold)).foregroundStyle(soft)
                }
                Text("лучшая серия подряд").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(soft)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(LinearGradient(colors: [c.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .klioGlass(22)
    }

    private func smallStat(_ value: Int, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            CountUp(target: value).font(.system(size: 23, weight: .heavy, design: .rounded)).foregroundStyle(ink)
            Text(LocalizedStringKey(label)).font(.system(size: 11, weight: .semibold)).foregroundStyle(soft).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).klioGlass(22)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(.system(size: 11, weight: .heavy)).tracking(1.3).foregroundStyle(soft).padding(.leading, 4)
            content()
        }
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            linkRow("Политика конфиденциальности", "lock.shield", privacyURL)
            Rectangle().fill(Color(hex: 0x786EAA).opacity(0.1)).frame(height: 1).padding(.leading, 58)
            linkRow("Условия использования", "doc.text", termsURL)
        }
        .padding(6).klioGlass(22)
    }

    private func linkRow(_ title: String, _ icon: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                iconBadge(icon, Color(hex: 0x8A7BFF))
                Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(soft)
            }
            .padding(.horizontal, 10).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconBadge(_ icon: String, _ color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.16))
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
        }.frame(width: 38, height: 38)
    }

    private func loadStats() async {
        if Demo.enabled { activeGoals = 5; bestStreak = 21; totalDone = 174; return }
        if let goals: [GoalResponse] = try? await APIClient.shared.request("goals", token: session.token) {
            activeGoals = goals.count
            bestStreak = goals.map { $0.currentStreak }.max() ?? 0
        }
    }
    private func loadSpheres() async {
        if Demo.enabled { spheres = Demo.spheres(); return }
        spheres = (try? await APIClient.shared.request("analytics/spheres", token: session.token)) ?? []
    }

    private var displayName: String { profile?.name?.isEmpty == false ? profile!.name! : "Профиль" }
    private var memberLine: String {
        let n = spheres.count
        return n > 0 ? String(format: L("участник Klio · %lld сфер роста"), n) : L("участник Klio")
    }

    private var initials: String {
        let source = profile?.name?.isEmpty == false ? profile!.name! : "•"
        let parts = source.split(separator: " ")
        let a = parts.first.map { String($0.prefix(1)) } ?? ""
        let b = parts.dropFirst().first.map { String($0.prefix(1)) } ?? ""
        return (a + b).uppercased()
    }

    // Пастельная палитра в тон фону/ауре: сферы различаются оттенком, а не кричащим хюэ.
    private func sphereStyle(_ icon: String) -> (icon: String, color: Color) {
        switch icon {
        case "lungs": return ("lungs.fill", Color(hex: 0x73B6C4))
        case "heart": return ("heart.fill", Color(hex: 0xE48AAE))
        case "brain": return ("brain.head.profile", Color(hex: 0x9B8CEF))
        case "energy", "bolt": return ("bolt.fill", Color(hex: 0xE3A878))
        case "sleep": return ("moon.fill", Color(hex: 0x8AA0E0))
        case "mood": return ("face.smiling.fill", Color(hex: 0x86C2A8))
        case "weight", "figure": return ("figure.run", Color(hex: 0xA6B98C))
        case "skin": return ("sparkles", Color(hex: 0xDBA0C8))
        case "drop": return ("drop.fill", Color(hex: 0x86B6E0))
        case "clock": return ("clock.fill", Color(hex: 0x9AA6C4))
        case "money": return ("rublesigncircle.fill", Color(hex: 0x86C2A8))
        default: return ("sparkles", Color(hex: 0x9B8CEF))
        }
    }

    // MARK: Info card (tappable rows)

    private func infoCard(_ p: ProfileResponse) -> some View {
        let rows: [(ProfileField, String)] = [
            (.name, p.name?.isEmpty == false ? p.name! : "—"),
            (.dob, formatBirthday(p.dateOfBirth)),
            (.gender, genderLabel(p.gender)),
            (.height, p.heightCm.map { "\(Int($0)) см" } ?? "—"),
            (.weight, p.weightKg.map { String(format: "%.1f кг", $0) } ?? "—"),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Rectangle().fill(Color(hex: 0x786EAA).opacity(0.1)).frame(height: 1).padding(.leading, 58) }
                Button { Haptic.tap(); editing = row.0 } label: { infoRow(field: row.0, value: row.1) }
                    .buttonStyle(KlioPress(scale: 0.99))
            }
        }
        .padding(6).klioGlass(22)
    }

    private func infoRow(field: ProfileField, value: String) -> some View {
        HStack(spacing: 14) {
            iconBadge(field.icon, sphereColorForField(field))
            VStack(alignment: .leading, spacing: 2) {
                Text(L(field.title).uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(soft)
                Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
            }
            Spacer()
            Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(soft)
        }
        .padding(.horizontal, 10).padding(.vertical, 11).contentShape(Rectangle())
    }

    private func sphereColorForField(_ f: ProfileField) -> Color {
        [Color(hex: 0x8A7BFF), Color(hex: 0xFF7EB3), Color(hex: 0x4FA293), Color(hex: 0xE8A35C), Color(hex: 0x5E83A8)][f.tint % 5]
    }

    // MARK: Account

    private var accountCard: some View {
        VStack(spacing: 0) {
            Button { Haptic.tap(); showLogoutConfirm = true } label: {
                accountRow("Выйти", "rectangle.portrait.and.arrow.right", ink, loading: false)
            }.buttonStyle(KlioPress(scale: 0.99))
            Rectangle().fill(Color(hex: 0x786EAA).opacity(0.1)).frame(height: 1).padding(.leading, 58)
            Button { Haptic.tap(); showDeleteConfirm = true } label: {
                accountRow("Удалить аккаунт", "trash", Color(hex: 0xCB5A4A), loading: isDeleting)
            }.buttonStyle(KlioPress(scale: 0.99)).disabled(isDeleting)
        }
        .padding(6).klioGlass(22)
    }

    private func accountRow(_ title: String, _ icon: String, _ color: Color, loading: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.14))
                if loading { ProgressView().tint(color).scaleEffect(0.8) }
                else { Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(color) }
            }.frame(width: 38, height: 38)
            Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 11).contentShape(Rectangle())
    }

    // MARK: Data

    private func genderLabel(_ g: String?) -> String {
        switch g {
        case "male": return L("Мужской")
        case "female": return L("Женский")
        default: return "—"
        }
    }

    private func formatBirthday(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"; inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inFmt.date(from: raw) else { return raw }
        let outFmt = DateFormatter()
        outFmt.locale = LocaleManager.shared.locale; outFmt.dateFormat = "d MMMM yyyy"
        return outFmt.string(from: date)
    }

    private func loadProfile() async {
        if Demo.enabled { profile = Demo.profile(); return }
        profile = try? await APIClient.shared.request("profile", token: session.token)
    }

    private func save(_ patch: ProfilePatch) async {
        if Demo.enabled { return }
        _ = try? await APIClient.shared.request(
            "profile", method: "PUT", body: patch, token: session.token
        ) as ProfileResponse
        await loadProfile()
    }

    private func deleteAccount() async {
        if Demo.enabled { dismiss(); session.logout(); return }
        isDeleting = true
        do {
            try await APIClient.shared.requestEmpty("profile/me", method: "DELETE", token: session.token)
            session.logout()
        } catch {
            isDeleting = false
            showDeleteError = true
        }
    }
}

// MARK: - Single-field editor

struct ProfileFieldEditor: View {
    let field: ProfileField
    let profile: ProfileResponse?
    let onSave: (ProfilePatch) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameVal = ""
    @State private var dob = Date()
    @State private var gender = "male"
    @State private var num = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Klio.tint(field.tint).opacity(0.14))
                    Image(systemName: field.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(Klio.tint(field.tint))
                }
                .frame(width: 40, height: 40)
                Text(LocalizedStringKey(field.title)).font(.klioTitle(18, .bold)).foregroundStyle(Klio.ink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 16)

            control.padding(.horizontal, 20)

            Spacer(minLength: 0)

            Button { Task { saving = true; await onSave(patch); dismiss() } } label: {
                Group {
                    if saving { ProgressView().tint(.white) }
                    else { Text("Сохранить").font(.klioText(16, .semibold)) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Klio.gradient(field.tint))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(Klio.bg)
        .onAppear(perform: seed)
    }

    @ViewBuilder
    private var control: some View {
        switch field {
        case .name:
            TextField("Имя", text: $nameVal)
                .font(.klioTitle(20, .semibold)).foregroundStyle(Klio.ink).focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Klio.surface).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onAppear { focused = true }
        case .dob:
            DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden().environment(\.locale, LocaleManager.shared.locale)
        case .gender:
            HStack(spacing: 10) {
                genderPill("Мужской", "male")
                genderPill("Женский", "female")
            }
        case .height, .weight:
            HStack(spacing: 8) {
                TextField("0", text: $num).keyboardType(.decimalPad).focused($focused)
                    .font(.klioNumber(30)).foregroundStyle(Klio.ink)
                Text(field == .height ? "см" : "кг").font(.klioText(16)).foregroundStyle(Klio.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Klio.surface).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear { focused = true }
        }
    }

    private func genderPill(_ title: String, _ value: String) -> some View {
        let active = gender == value
        return Button { gender = value } label: {
            Text(LocalizedStringKey(title)).font(.klioText(15, .semibold))
                .foregroundStyle(active ? .white : Klio.inkSoft)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(active ? AnyShapeStyle(Klio.gradient(field.tint)) : AnyShapeStyle(Klio.surface))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var patch: ProfilePatch {
        switch field {
        case .name: return ProfilePatch(name: nameVal)
        case .dob:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            return ProfilePatch(dateOfBirth: f.string(from: dob))
        case .gender: return ProfilePatch(gender: gender)
        case .height: return ProfilePatch(heightCm: num.decimalDouble)
        case .weight: return ProfilePatch(weightKg: num.decimalDouble)
        }
    }

    private func seed() {
        guard let p = profile else { return }
        nameVal = p.name ?? ""
        gender = p.gender ?? "male"
        if let raw = p.dateOfBirth {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            dob = f.date(from: raw) ?? Date()
        }
        switch field {
        case .height: num = p.heightCm.map { "\(Int($0))" } ?? ""
        case .weight: num = p.weightKg.map { $0.clean } ?? ""
        default: break
        }
    }
}

// MARK: - Profile helpers

private struct ProfileScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Плавный счёт от 0 до target с ease-out при появлении.
struct CountUp: View {
    let target: Int
    var duration: Double = 0.9
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { ctx in
            let p = min(max(ctx.date.timeIntervalSince(start) / duration, 0), 1)
            let eased = 1 - pow(1 - p, 3)
            Text("\(Int(Double(target) * eased))")
        }
    }
}

private extension View {
    /// Каскадное появление секций: всплытие снизу + fade с задержкой по индексу.
    func reveal(_ on: Bool, index: Int) -> some View {
        self.opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 22)
            .animation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.06 * Double(index)), value: on)
    }
}

private func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    let w = (m10 == 1 && m100 != 11) ? one : ((2...4).contains(m10) && !(12...14).contains(m100) ? few : many)
    return "\(n) \(w)"
}
