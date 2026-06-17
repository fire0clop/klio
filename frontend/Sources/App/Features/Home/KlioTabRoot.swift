import SwiftUI

// Корень v3: бар Сегодня · Прогресс · (+) · Разбор · Профиль.

struct KlioTabRoot: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var vm = DashboardViewModel()
    @State private var tab = Int(ProcessInfo.processInfo.environment["KLIO_TAB"] ?? "") ?? 0
    @State private var showCreate = ProcessInfo.processInfo.environment["KLIO_CREATE"] == "1"

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case 0: TodayWaves(vm: vm, onCreate: { showCreate = true })
                case 1: ProgressTab()
                case 2: RazborTab()
                default: ProfileView(showsClose: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KlioTabBar(tab: $tab)
        }
        .task { if vm.checkin == nil { await loadToday() } }
        .sheet(isPresented: $showCreate) {
            GoalCreationView { showCreate = false; Task { await loadToday() } }
        }
    }

    private func loadToday() async {
        if Demo.enabled { vm.loadDemo(); return }
        await vm.load(token: session.token)
    }
}

// MARK: - Floating glass navigation (отдельные плавающие пилюли, без единого блока)

struct KlioTabBar: View {
    @Binding var tab: Int

    private let tabs: [(label: String, icon: String)] = [
        ("Сегодня", "sun.max.fill"),
        ("Прогресс", "chart.bar.fill"),
        ("Разбор", "sparkles"),
        ("Профиль", "person.fill"),
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in
                item(i, t.label, t.icon)
            }
        }
        .padding(.bottom, 6)
    }

    private func item(_ idx: Int, _ label: String, _ icon: String) -> some View {
        let isActive = tab == idx
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { tab = idx }
            Haptic.tap()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                if isActive {
                    Text(LocalizedStringKey(label)).font(.system(size: 13, weight: .heavy)).fixedSize()
                }
            }
            .foregroundStyle(isActive ? .white : Color(hex: 0x544E70))
            .padding(.horizontal, isActive ? 18 : 0)
            .frame(width: isActive ? nil : 54, height: 54)
            .background(navBackground(isActive))
            .overlay(
                Capsule().stroke(.white.opacity(isActive ? 0 : 0.65), lineWidth: 1)
            )
            .shadow(color: isActive ? Color(hex: 0x8A7BFF).opacity(0.4) : Color(hex: 0x785AA0).opacity(0.18),
                    radius: isActive ? 14 : 9, y: isActive ? 6 : 4)
        }
        .buttonStyle(KlioPress(scale: 0.9))
    }

    @ViewBuilder
    private func navBackground(_ isActive: Bool) -> some View {
        if isActive {
            Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.35)))
        }
    }
}


// MARK: - Razbor tab (разбор от ИИ)

struct RazborTab: View {
    @EnvironmentObject var session: SessionStore
    @State private var insights: [InsightResponse] = []
    @State private var spheres: [SphereResponse] = []
    @State private var loading = true
    @State private var page = 0
    @State private var expanded: String?
    @State private var sphereSeries: [String: [Double]] = [:]

    private let ink = Color(hex: 0x2B2545)
    private let soft = Color(hex: 0x544E70)

    private var ordered: [InsightResponse] {
        let r = insights.filter { $0.kind == "reaction" }
        let rest = insights.filter { $0.kind != "reaction" }
        return r + rest
    }

    var body: some View {
        ZStack {
            KlioMeshBg()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Разбор").font(.system(size: 30, weight: .heavy)).foregroundStyle(ink)
                        Text("Реакция ИИ и твои растущие сферы").font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
                    }
                    .padding(.horizontal, 18).padding(.top, 14)

                    if loading {
                        loadingState.padding(.horizontal, 18)
                    } else if insights.isEmpty && spheres.isEmpty {
                        emptyState.padding(.horizontal, 18)
                    } else {
                        if !ordered.isEmpty { slider }
                        if !spheres.isEmpty { spheresSection.padding(.horizontal, 18) }
                    }
                    Spacer(minLength: 130)
                }
                .klioReadable()
            }
            .scrollIndicators(.hidden)
            .refreshable { await refresh() }
        }
        .task { await load() }
    }

    // MARK: Insights slider

    private var slider: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ОТ ИИ").font(.system(size: 11, weight: .heavy)).tracking(1.3).foregroundStyle(soft)
                .padding(.horizontal, 22)
            TabView(selection: $page) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, item in
                    slideCard(item).padding(.horizontal, 18).padding(.bottom, 36).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 268)
        }
        .padding(.top, 4)
    }

    private func slideCard(_ item: InsightResponse) -> some View {
        let isReaction = item.kind == "reaction"
        let s = kindStyle(item.kind)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isReaction
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(s.color.opacity(0.16)))
                        .frame(width: 40, height: 40)
                    Image(systemName: s.icon).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isReaction ? .white : s.color)
                }
                Text(L(isReaction ? "Реакция на вчера" : s.label).uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(1.1).foregroundStyle(isReaction ? Color(hex: 0x8A7BFF) : s.color)
                Spacer()
            }
            if let t = item.title, !t.isEmpty {
                Text(t).font(.system(size: 19, weight: .heavy)).foregroundStyle(ink).lineLimit(2)
            }
            Text(item.content).font(.system(size: 15, weight: .medium)).foregroundStyle(Color(hex: 0x3A3458))
                .lineSpacing(3).lineLimit(5).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).klioGlass(26)
    }

    // MARK: Spheres

    private var spheresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("СФЕРЫ И НАВЫКИ").font(.system(size: 11, weight: .heavy)).tracking(1.3).foregroundStyle(soft)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(spheres.enumerated()), id: \.element.id) { i, sp in
                    if i > 0 { Rectangle().fill(Color(hex: 0x786EAA).opacity(0.1)).frame(height: 1).padding(.vertical, 4) }
                    sphereRow(sp)
                }
            }
            .padding(16).klioGlass(24)
        }
    }

    private func sphereRow(_ sp: SphereResponse) -> some View {
        let st = sphereStyle(sp.icon)
        let isOpen = expanded == sp.icon
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                expanded = isOpen ? nil : sp.icon
            }
            Haptic.tap()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(st.color.opacity(0.16)).frame(width: 40, height: 40)
                        Image(systemName: st.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(st.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sp.name).font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                        if !sp.caption.isEmpty {
                            Text(sp.caption).font(.system(size: 12, weight: .medium)).foregroundStyle(soft)
                                .lineLimit(isOpen ? nil : 2).fixedSize(horizontal: false, vertical: true)
                        } else if !sp.goals.isEmpty {
                            Text(sp.goals.joined(separator: " · ")).font(.system(size: 12, weight: .medium)).foregroundStyle(soft).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    VStack(spacing: 4) {
                        Text("\(sp.percent)%").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(st.color)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)).foregroundStyle(soft.opacity(0.6))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x786EAA).opacity(0.12)).frame(height: 8)
                        Capsule().fill(LinearGradient(colors: [st.color.opacity(0.7), st.color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * CGFloat(min(sp.percent, 100)) / 100, 8), height: 8)
                    }
                }
                .frame(height: 8)

                if isOpen { expandedDetail(sp, color: st.color) }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func expandedDetail(_ sp: SphereResponse, color: Color) -> some View {
        let series = sphereSeries[sp.icon] ?? []
        let delta = (series.last ?? 0) - (series.first ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("ПО ДНЯМ · 4 НЕДЕЛИ").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(soft)
                if !series.isEmpty {
                    let up = delta >= 0
                    HStack(spacing: 2) {
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .heavy))
                        Text("\(up ? "+" : "")\(Int(delta))").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(up ? Color(hex: 0x3FAE8E) : Color(hex: 0xCB6A4A))
                }
                Spacer()
                if !sp.goals.isEmpty {
                    Text(sp.goals.joined(separator: ", ")).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(soft.opacity(0.75)).lineLimit(1)
                }
            }
            if series.count >= 2 {
                dayChart(series, color: color)
            } else {
                Text("Пока копим данные — кривая появится после нескольких дней отметок.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(soft)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        }
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // График по дням 0..100: рост в дни выполнения, падение в пропуски.
    private func dayChart(_ series: [Double], color: Color) -> some View {
        let lo = max(0, (series.min() ?? 0) - 6)
        let hi = min(100, (series.max() ?? 100) + 6)
        let range = max(hi - lo, 1)
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = max(series.count, 2)
            let pts: [CGPoint] = series.enumerated().map { i, v in
                CGPoint(x: w * CGFloat(i) / CGFloat(n - 1), y: h - h * CGFloat((v - lo) / range))
            }
            ZStack {
                // базовая линия
                Path { p in p.move(to: CGPoint(x: 0, y: h - 0.5)); p.addLine(to: CGPoint(x: w, y: h - 0.5)) }
                    .stroke(Color(hex: 0x786EAA).opacity(0.12), lineWidth: 1)
                // заливка
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: h)); p.addLine(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                    if let l = pts.last { p.addLine(to: CGPoint(x: l.x, y: h)) }
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                // линия (градиент в цвет сферы)
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing),
                        style: .init(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                // точка-конец
                if let l = pts.last {
                    Circle().fill(color).frame(width: 14, height: 14).opacity(0.18).position(l)
                    Circle().fill(.white).frame(width: 9, height: 9).overlay(Circle().stroke(color, lineWidth: 2.6)).position(l)
                }
            }
        }
        .frame(height: 70)
    }

    private func sphereStyle(_ icon: String) -> (icon: String, color: Color) {
        switch icon {
        case "lungs": return ("lungs.fill", Color(hex: 0x4FA293))
        case "heart": return ("heart.fill", Color(hex: 0xE0607A))
        case "brain": return ("brain.head.profile", Color(hex: 0x8A7BFF))
        case "energy": return ("bolt.fill", Color(hex: 0xE8A35C))
        case "sleep": return ("moon.fill", Color(hex: 0x5E83A8))
        case "mood": return ("face.smiling.fill", Color(hex: 0x4F9E86))
        case "weight": return ("figure.run", Color(hex: 0x7E9667))
        case "skin": return ("sparkles", Color(hex: 0xD18AA0))
        case "clock": return ("clock.fill", Color(hex: 0x6E8C9C))
        case "money": return ("rublesigncircle.fill", Color(hex: 0x4F9E86))
        default: return ("sparkles", Color(hex: 0x8A7BFF))
        }
    }

    private func kindStyle(_ k: String?) -> (icon: String, color: Color, label: String) {
        switch k {
        case "win": return ("checkmark.seal.fill", Color(hex: 0x4F9E86), "Победа")
        case "watch": return ("exclamationmark.triangle.fill", Color(hex: 0xCB8A45), "Внимание")
        case "trend": return ("chart.line.uptrend.xyaxis", Color(hex: 0x7D82D8), "Динамика")
        case "tip": return ("lightbulb.fill", Color(hex: 0x5E83A8), "Совет")
        default: return ("sparkles", Color(hex: 0x8A7BFF), "Реакция")
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: 14) {
            FlameMark(size: 40)
            Text("ИИ читает твой день…").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
            ProgressView().tint(Color(hex: 0x8A7BFF))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50).klioGlass(26)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 38)).foregroundStyle(Color(hex: 0x8A7BFF).opacity(0.6))
            Text("Пока недостаточно данных").font(.system(size: 16, weight: .bold)).foregroundStyle(ink)
            Text("Отмечай цели пару дней — и здесь появится\nреакция ИИ и рост твоих сфер.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(soft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44).klioGlass(26)
    }

    // MARK: Data

    private func load() async {
        loading = true
        if Demo.enabled {
            insights = Demo.insights(); spheres = Demo.spheres(); loading = false
        } else {
            async let ins: [InsightResponse]? = try? await APIClient.shared.request("analytics/insights", token: session.token)
            async let sph: [SphereResponse]? = try? await APIClient.shared.request("analytics/spheres", token: session.token)
            insights = (await ins) ?? []
            spheres = (await sph) ?? []
            loading = false
        }
        await computeSeries()
        if ProcessInfo.processInfo.environment["KLIO_EXPAND"] == "1" { expanded = spheres.first?.icon }
    }
    private func refresh() async {
        if Demo.enabled { return }
        if let fresh: [InsightResponse] = try? await APIClient.shared.request("analytics/insights/refresh", method: "POST", token: session.token) {
            insights = fresh
        }
        if let sph: [SphereResponse] = try? await APIClient.shared.request("analytics/spheres", token: session.token) {
            spheres = sph
        }
        await computeSeries()
    }

    private let trajSpan = 28

    // Дневная траектория сферы: растёт в дни выполнения целей, падает в пропуски.
    // Привязана к текущему проценту (последняя точка = sp.percent), чтобы график был «про процент».
    private func computeSeries() async {
        if Demo.enabled {
            for (i, sp) in spheres.enumerated() {
                var ratios: [Double] = []
                for d in 0..<trajSpan {
                    let missed = ((d * 3 + i * 5) % 7 == 2) || ((d + i * 2) % 9 == 0)
                    ratios.append(missed ? 0 : 1)
                }
                sphereSeries[sp.icon] = trajectory(dayRatios: ratios, percent: sp.percent)
            }
            return
        }
        guard let goals: [GoalResponse] = try? await APIClient.shared.request("goals", token: session.token) else { return }
        let needed = Set(spheres.flatMap { $0.goals })
        var hist: [UUID: [HistoryPoint]] = [:]
        for g in goals where needed.contains(g.title) {
            if let h: [HistoryPoint] = try? await APIClient.shared.request("goals/\(g.id)/history?days=\(trajSpan)", token: session.token) {
                hist[g.id] = h
            }
        }
        var result: [String: [Double]] = [:]
        for sp in spheres {
            let ids = sp.goals.compactMap { t in goals.first { $0.title == t }?.id }
            result[sp.icon] = trajectory(dayRatios: dailyRatios(ids: ids, hist: hist), percent: sp.percent)
        }
        sphereSeries = result
    }

    // Доля выполнения по дням (0..1) за trajSpan дней, today — последний.
    private func dailyRatios(ids: [UUID], hist: [UUID: [HistoryPoint]]) -> [Double] {
        var out: [Double] = []
        for d in 0..<trajSpan {
            var rs: [Double] = []
            for id in ids {
                let points: [HistoryPoint] = hist[id] ?? []
                let tail: [Bool] = Array(points.suffix(trajSpan)).map { $0.completed }
                let padded: [Bool] = Array(repeating: false, count: max(0, trajSpan - tail.count)) + tail
                rs.append(padded[d] ? 1 : 0)
            }
            out.append(rs.isEmpty ? 0 : rs.reduce(0, +) / Double(rs.count))
        }
        return out
    }

    // День выполнен → значение растёт, пропущен → падает. Привязка конца к текущему %.
    private func trajectory(dayRatios: [Double], percent: Int) -> [Double] {
        let step = 9.0
        var v = 0.0
        var traj: [Double] = []
        for r in dayRatios {
            v += (r - 0.45) * step
            v = min(100, max(0, v))
            traj.append(v)
        }
        guard let last = traj.last else { return traj }
        let shift = Double(percent) - last
        return traj.map { min(100, max(0, $0 + shift)) }
    }
}
