import SwiftUI

// «Сегодня» v3 — волновой герой (58) + карточки-полосы с заливкой (57).
// Светлое розово-голубое стекло, нарисованный огонёк, заливка блока слева-направо,
// быстрый тап для целей-фактов, перелив при переборе лимита.

struct TodayWaves: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var vm: DashboardViewModel
    var onCreate: () -> Void

    @State private var editing: UUID?
    @State private var history: [UUID: [HistoryPoint]] = [:]
    @State private var rowOffset: [UUID: CGFloat] = [:]
    @State private var pendingDelete: GoalCheckInItem?

    private var goals: [GoalCheckInItem] { vm.checkin?.goals ?? [] }
    private var passGoals: [GoalCheckInItem] { goals.filter { $0.kind != .valueLog } }

    // Самоцветная палитра в семье розово-голубого стекла: ярко, но без землистых тонов.
    private let palette: [Color] = [
        Color(hex: 0xEC6FA0), Color(hex: 0xF2A24E), Color(hex: 0x4FA6DE),
        Color(hex: 0xA77BE0), Color(hex: 0x3FBFA8), Color(hex: 0x6E84D8),
    ]
    private func ac(_ g: GoalCheckInItem) -> Color {
        palette[abs(goals.firstIndex(where: { $0.id == g.id }) ?? 0) % palette.count]
    }

    var body: some View {
        ZStack {
            KlioMeshBg().onTapGesture { UIApplication.shared.dismissKeyboard() }
            if vm.isLoading && vm.checkin == nil {
                ProgressView().tint(Color(hex: 0x8A7BFF))
            } else if goals.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        streakCard.padding(.top, 16)
                        Text("Привычки сегодня")
                            .font(.system(size: 15, weight: .heavy)).foregroundStyle(Color(hex: 0x2B2545))
                            .padding(.leading, 4).padding(.top, 22).padding(.bottom, 12)
                        VStack(spacing: 12) { ForEach(goals) { swipeRow($0) } }
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 18).padding(.top, 6)
                    .klioReadable()
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: goals.map { $0.id }) { await loadHistories() }
        .sheet(item: Binding(get: { editing.flatMap { id in goals.first { $0.id == id } } }, set: { _ in editing = nil })) { goal in
            KeypadSheet(
                title: goal.title, unit: goal.displayUnit, kind: goal.kind, target: goal.todayTarget,
                tint: ac(goal).opacity(0.12),
                text: Binding(get: { vm.actualValues[goal.goalId] ?? "" }, set: { vm.actualValues[goal.goalId] = $0 }),
                onDone: { editing = nil; commit() }
            )
            .presentationDetents([.height(560)]).presentationDragIndicator(.visible)
        }
        .alert("Удалить цель?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { closeSwipe(pendingDelete); pendingDelete = nil } }
        )) {
            Button("Отмена", role: .cancel) { closeSwipe(pendingDelete); pendingDelete = nil }
            Button("Удалить", role: .destructive) {
                if let g = pendingDelete { Task { await deleteGoal(g) } }
                pendingDelete = nil
            }
        } message: {
            Text("«\(pendingDelete?.title ?? "")» и вся её история будут удалены безвозвратно.")
        }
    }

    // MARK: Swipe-to-delete

    private func swipeRow(_ g: GoalCheckInItem) -> some View {
        let off = rowOffset[g.id] ?? 0
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0xCB6A4A))
                .frame(width: max(-off, 0))
                .overlay(
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .opacity(-off > 44 ? 1 : 0)
                )
                .onTapGesture { Haptic.tap(.medium); pendingDelete = g }
            bar(g)
                .offset(x: off)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            let base: CGFloat = (rowOffset[g.id] ?? 0) <= -84 ? -84 : 0
                            rowOffset[g.id] = min(0, max(base + v.translation.width, -84))
                        }
                        .onEnded { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                if v.translation.width < -160 { rowOffset[g.id] = 0; Haptic.tap(.medium); pendingDelete = g }
                                else { rowOffset[g.id] = v.translation.width < -46 ? -84 : 0 }
                            }
                        }
                )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: off)
    }

    private func closeSwipe(_ g: GoalCheckInItem?) {
        guard let g else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { rowOffset[g.id] = 0 }
    }

    private func deleteGoal(_ g: GoalCheckInItem) async {
        rowOffset[g.id] = 0
        if Demo.enabled {
            if let c = vm.checkin {
                vm.checkin = CheckInTodayResponse(date: c.date, goals: c.goals.filter { $0.id != g.id }, dailyLog: c.dailyLog, allDone: c.allDone)
            }
            return
        }
        try? await APIClient.shared.requestEmpty("goals/\(g.goalId)", method: "DELETE", token: session.token)
        await vm.load(token: session.token)
        await loadHistories()
    }

    // MARK: Hero

    private var header: some View {
        HStack(spacing: 14) {
            FlameMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x544E70))
                Text("Klio").font(.system(size: 25, weight: .heavy)).foregroundStyle(Color(hex: 0x2B2545))
                Text(dateLine).font(.system(size: 12)).foregroundStyle(Color(hex: 0x544E70))
            }
            Spacer()
            Button(action: onCreate) {
                Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
                    .shadow(color: Color(hex: 0x8A7BFF).opacity(0.35), radius: 8, y: 4)
            }
        }
        .padding(.top, 4)
    }

    private var streakCard: some View {
        let streak = streakRun
        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(streak)")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .leading, endPoint: .trailing))
                    Text("дней подряд").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x544E70))
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { i, lbl in
                        let on = weekdayStates[i]
                        Text(LocalizedStringKey(lbl))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(on ? .white : Color(hex: 0x9A93B0))
                            .frame(width: 25, height: 31)
                            .background(
                                on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .top, endPoint: .bottom))
                                   : AnyShapeStyle(Color(hex: 0x786EAA).opacity(0.15)))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)
            ZStack {
                WaveShape(phase: 0, amp: 3, wavelength: 135).fill(waveGrad.opacity(0.16))
                WaveShape(phase: .pi, amp: 3, wavelength: 135).fill(waveGrad.opacity(0.3))
            }
            .frame(height: 20)
        }
        .background(glassBase(28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: Color(hex: 0x785AA0).opacity(0.16), radius: 14, y: 8)
    }

    private var waveGrad: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Habit fill-bar

    private func bar(_ g: GoalCheckInItem) -> some View {
        let color = ac(g)
        let frac = fillFraction(g)
        let light = frac >= 0.42
        let over = isOver(g)
        return Button { tap(g) } label: {
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    LinearGradient(colors: [lighten(color, 0.28), color], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(geo.size.width * frac, frac > 0 ? 24 : 0))
                        .clipShape(.rect(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 18, topTrailingRadius: 18))
                        .opacity(0.9)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: frac)
                }
                HStack(spacing: 13) {
                    Image(systemName: iconFor2(g))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(light ? .white : color)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(light ? .white : Color(hex: 0x2B2545)).lineLimit(1)
                        Text(subtitle(g)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(light ? .white.opacity(0.92) : Color(hex: 0x4B4368)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    rightControl(g, color: color, over: over)
                }
                .padding(.horizontal, 16)
                if over {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                        .offset(x: 0, y: -22).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 18)
                }
            }
            .frame(height: 76)
            .background(glassBase(22))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1))
            .shadow(color: Color(hex: 0x785AA0).opacity(0.14), radius: 12, y: 6)
        }
        .buttonStyle(TilePress(scale: 0.98))
    }

    @ViewBuilder
    private func rightControl(_ g: GoalCheckInItem, color: Color, over: Bool) -> some View {
        if over {
            // Перебор лимита: показываем насколько превысил.
            Text("+\((actual(g) - (g.todayTarget ?? 0)).cl)")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color(hex: 0xCB6A4A)).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if g.kind == .fact || isAbstinence(g) || isDone(g) {
            checkMark(done: isDone(g), color: color)
        } else if g.kind == .quantUp {
            // Прогресс к цели «не менее».
            Text("\(Int((fillFraction(g) * 100).rounded()))%")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(color)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.white.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            // «Не более», ещё не отмечено сегодня.
            Text("отметить")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.65)).clipShape(Capsule())
        }
    }

    // Не выполнено: тонкое кольцо в цвет цели (видно на белом). Выполнено: жемчужный белый
    // диск + draw-on галочка в цвет цели + мягкое цветное свечение. Чёрного нет; контраст
    // даёт белый диск (на цветной заливке) и цветное кольцо (на белой карточке).
    private func checkMark(done: Bool, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(done ? 0.95 : 0.0))
                .overlay(Circle().stroke(color.opacity(done ? 0 : 0.5), lineWidth: 2))
                .frame(width: 34, height: 34)
                .shadow(color: done ? color.opacity(0.3) : .clear, radius: 6, y: 2)

            CheckTick()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 15)
                .opacity(done ? 1 : 0)
                .scaleEffect(done ? 1 : 0.6)
        }
        .frame(width: 46, height: 46)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.4, dampingFraction: 0.62), value: done)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            FlameMark(size: 54)
            Text("Поставь первую цель").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(hex: 0x2B2545))
            Button(action: onCreate) {
                Text("Создать").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 13)
                    .background(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0x8A7BFF)], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: Logic

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return L("Доброе утро")
        case 12..<18: return L("Добрый день")
        case 18..<23: return L("Добрый вечер")
        default: return L("Доброй ночи")
        }
    }
    private var dateLine: String {
        let f = DateFormatter(); f.locale = LocaleManager.shared.locale; f.dateFormat = "EEEE · d MMMM"
        return f.string(from: Date()).capitalizedFirst
    }
    private let dayLabels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    // Все цели выполнены k дней назад? (k=0 — сегодня, живое состояние)
    private func allDone(daysAgo k: Int) -> Bool {
        let gs = passGoals
        guard !gs.isEmpty else { return false }
        if k == 0 { return gs.allSatisfy { isDone($0) } }
        return gs.allSatisfy { g in
            let h = history[g.goalId] ?? []
            let idx = h.count - 1 - k
            return idx >= 0 && h[idx].completed
        }
    }
    // Серия = подряд идущие дни, где выполнены ВСЕ цели (сегодня не закрыт — считаем со вчера).
    private var streakRun: Int {
        var s = 0
        var k = allDone(daysAgo: 0) ? 0 : 1
        let maxK = (history.values.map { $0.count }.max() ?? 0) + 1
        while k <= maxK && allDone(daysAgo: k) { s += 1; k += 1 }
        return s
    }
    // Пилюля загорается, только если в ЭТОТ день выполнены ВСЕ цели; будущие дни — серые.
    private var weekdayStates: [Bool] {
        let wd = Calendar.current.component(.weekday, from: Date()) // 1=вс..7=сб
        let todayIdx = (wd + 5) % 7 // Пн=0 .. Вс=6
        guard !passGoals.isEmpty else { return Array(repeating: false, count: 7) }
        return (0..<7).map { i in i <= todayIdx && allDone(daysAgo: todayIdx - i) }
    }
    private func loadHistories() async {
        guard !goals.isEmpty else { return }
        if Demo.enabled { for g in goals { history[g.goalId] = Demo.history(days: 30) }; return }
        for g in goals {
            if let h: [HistoryPoint] = try? await APIClient.shared.request("goals/\(g.goalId)/history?days=30", token: session.token) {
                history[g.goalId] = h
            }
        }
    }

    private func actual(_ g: GoalCheckInItem) -> Double { vm.actualValues[g.goalId]?.decimalDouble ?? 0 }
    private func isAbstinence(_ g: GoalCheckInItem) -> Bool { g.kind == .quantDown && (g.todayTarget ?? 0) == 0 }
    private func iconFor2(_ g: GoalCheckInItem) -> String { g.icon ?? (isAbstinence(g) ? "nosign" : iconFor(g.title)) }
    private func isOver(_ g: GoalCheckInItem) -> Bool {
        g.kind == .quantDown && !isAbstinence(g) && (g.todayTarget.map { actual(g) > $0 } ?? false)
    }
    private func fillFraction(_ g: GoalCheckInItem) -> Double {
        switch g.kind {
        case .fact: return isDone(g) ? 1 : 0
        case .quantUp:
            // «не менее»: заливка = прогресс к цели; достиг/превысил → полная.
            guard let t = g.todayTarget, t > 0 else { return isDone(g) ? 1 : 0 }
            return min(actual(g) / t, 1)
        case .quantDown:
            // «не более»: уложился в лимит → выполнено (полная). Перебор → тоже полная (с переливом).
            if isAbstinence(g) { return isDone(g) ? 1 : 0 }
            return (isDone(g) || isOver(g)) ? 1 : 0
        case .valueLog: return isDone(g) ? 1 : 0
        }
    }
    private func isDone(_ g: GoalCheckInItem) -> Bool {
        switch g.kind {
        case .fact: return vm.completions[g.goalId] ?? false
        case .quantUp: guard let t = g.todayTarget, t > 0 else { return false }; return actual(g) >= t
        case .quantDown:
            if isAbstinence(g) { return vm.actualValues[g.goalId] != nil }
            guard let t = g.todayTarget else { return false }; return vm.actualValues[g.goalId] != nil && actual(g) <= t
        case .valueLog: return vm.actualValues[g.goalId] != nil
        }
    }
    private func subtitle(_ g: GoalCheckInItem) -> String {
        let s = g.currentStreak
        let flame = s > 0 ? " · 🔥 \(s)" : ""
        switch g.kind {
        case .fact: return L(isDone(g) ? "Сделано сегодня" : "Отметь выполнение") + flame
        case .quantUp:
            let base = g.todayTarget.map { "\(actual(g).cl) / \($0.cl) \(g.displayUnit)" } ?? g.displayUnit
            return base + (isDone(g) ? " · " + L("цель достигнута") : "") + flame
        case .quantDown:
            if isAbstinence(g) { return L(isDone(g) ? "Сегодня чисто" : "Отметь воздержание") + flame }
            let base = g.todayTarget.map { "\(actual(g).cl) / ≤ \($0.cl) \(g.displayUnit)" } ?? g.displayUnit
            let st = isOver(g) ? " · " + L("перебор") : (isDone(g) ? " · " + L("в норме") : "")
            return base + st + flame
        case .valueLog: return (g.target.map { "\((g.actualValueToday ?? actual(g)).cl) \(g.displayUnit) · \(L("цель")) \($0.cl)" } ?? g.displayUnit) + flame
        }
    }
    private func tap(_ g: GoalCheckInItem) {
        if g.kind == .fact { toggleFact(g) } else if isAbstinence(g) { toggleAbstinence(g) } else { editing = g.id }
    }
    private func toggleFact(_ g: GoalCheckInItem) {
        let cur = vm.completions[g.goalId] ?? false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vm.completions[g.goalId] = !cur }
        Haptic.tap(cur ? .light : .medium); commit()
    }
    private func toggleAbstinence(_ g: GoalCheckInItem) {
        let d = vm.actualValues[g.goalId] != nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vm.actualValues[g.goalId] = d ? nil : "0" }
        Haptic.tap(d ? .light : .medium); commit()
    }
    private func commit() { Task { await vm.commitNow(token: session.token) } }

    // helpers
    private func glassBase(_ r: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white.opacity(0.3))
        }
    }
    private func lighten(_ c: Color, _ amt: CGFloat) -> Color {
        let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: r + (1 - r) * amt, green: g + (1 - g) * amt, blue: b + (1 - b) * amt)
    }
}

// MARK: - Shared visual pieces

extension View {
    /// Светлая стеклянная подложка в языке Klio (frosted + лёгкий белый + контур + тень).
    func klioGlass(_ r: CGFloat = 24) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white.opacity(0.18)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous).stroke(
                    LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x785AA0).opacity(0.16), radius: 14, y: 7)
    }
}

extension View {
    /// На iPad ограничивает ширину контента и центрирует колонку; на iPhone — без изменений
    /// (iPhone уже уже, чем лимит, поэтому ограничение не срабатывает).
    func klioReadable(_ maxWidth: CGFloat = 680) -> some View {
        self.containerRelativeFrame(.horizontal, alignment: .center) { length, _ in
            min(length, maxWidth)
        }
    }
}

struct KlioMeshBg: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xFFE1EF), Color(hex: 0xD8E6FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0xFFB3D9).opacity(0.9), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(hex: 0xA9C7FF).opacity(0.9), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(hex: 0xD4C2FF).opacity(0.8), .clear], center: .bottom, startRadius: 0, endRadius: 340)
        }
        .ignoresSafeArea()
    }
}

// Нарисованный огонёк (градиент золото→розовый→фиолетовый), не эмодзи.
/// Силуэт капли-самоцвета — основа бренд-знака и иконки приложения.
struct GemDrop: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 0.50 * w, y: 0.04 * h))
        p.addCurve(to: CGPoint(x: 0.93 * w, y: 0.60 * h),
                   control1: CGPoint(x: 0.67 * w, y: 0.16 * h), control2: CGPoint(x: 0.93 * w, y: 0.40 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.96 * h),
                   control1: CGPoint(x: 0.93 * w, y: 0.80 * h), control2: CGPoint(x: 0.74 * w, y: 0.96 * h))
        p.addCurve(to: CGPoint(x: 0.07 * w, y: 0.60 * h),
                   control1: CGPoint(x: 0.26 * w, y: 0.96 * h), control2: CGPoint(x: 0.07 * w, y: 0.80 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.04 * h),
                   control1: CGPoint(x: 0.07 * w, y: 0.40 * h), control2: CGPoint(x: 0.33 * w, y: 0.16 * h))
        p.closeSubpath()
        return p
    }
}

/// Бренд-знак Klio — мини-самоцвет, совпадает с иконкой приложения.
struct GemMark: View {
    var size: CGFloat = 38
    var body: some View {
        GemDrop()
            .fill(LinearGradient(colors: [Color(hex: 0xFF7EB3), Color(hex: 0xB07BE8), Color(hex: 0x7E6BFF)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                ZStack {
                    // насыщенное ядро
                    Ellipse().fill(Color(hex: 0x6A4FD8).opacity(0.30))
                        .frame(width: size * 0.5, height: size * 0.5)
                        .offset(y: size * 0.12).blur(radius: size * 0.12)
                    // стеклянный блик вдоль верхне-левой грани
                    Capsule().fill(.white.opacity(0.55))
                        .frame(width: size * 0.10, height: size * 0.32)
                        .rotationEffect(.degrees(-20))
                        .offset(x: -size * 0.13, y: -size * 0.05)
                        .blur(radius: size * 0.022)
                    // блик на кончике
                    Ellipse().fill(.white.opacity(0.5))
                        .frame(width: size * 0.12, height: size * 0.09)
                        .offset(y: -size * 0.30).blur(radius: size * 0.02)
                }
                .clipShape(GemDrop())
            )
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0x8A7BFF).opacity(0.30), radius: size * 0.14, y: size * 0.05)
    }
}

// Старое имя для обратной совместимости вызовов.
typealias FlameMark = GemMark

// Галочка в нормированном квадрате — стабильный порядок точек для draw-on (trim).
struct CheckTick: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0.16 * w, y: 0.55 * h))
        p.addLine(to: CGPoint(x: 0.42 * w, y: 0.80 * h))
        p.addLine(to: CGPoint(x: 0.86 * w, y: 0.24 * h))
        return p
    }
}

struct WaveShape: Shape {
    var phase: CGFloat = 0
    var amp: CGFloat = 5
    var wavelength: CGFloat = 85
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.height * 0.42
        p.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        while x <= rect.width {
            let y = midY - amp * sin((x / wavelength) * 2 * .pi + phase)
            p.addLine(to: CGPoint(x: x, y: y)); x += 3
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

private extension Double {
    var cl: String { truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self) }
}
private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
