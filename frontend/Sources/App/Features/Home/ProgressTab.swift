import SwiftUI

// «Прогресс» — общий недельный бар-виджет (как референс) + развёртка ИСТОРИИ по каждой
// цели в формате сетки дней (не график): видно выполнение, серию и процент за период.

struct ProgressTab: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var vm = DashboardViewModel()
    @State private var history: [UUID: [HistoryPoint]] = [:]
    private let window = 35

    private var goals: [GoalCheckInItem] { vm.checkin?.goals ?? [] }

    // Та же самоцветная палитра, что на «Сегодня» (розово-голубая семья, без землистых).
    private let palette: [Color] = [
        Color(hex: 0xEC6FA0), Color(hex: 0xF2A24E), Color(hex: 0x4FA6DE),
        Color(hex: 0xA77BE0), Color(hex: 0x3FBFA8), Color(hex: 0x6E84D8),
    ]
    private func ac(_ g: GoalCheckInItem) -> Color {
        palette[abs(goals.firstIndex(where: { $0.id == g.id }) ?? 0) % palette.count]
    }
    private let ink = Color(hex: 0x2B2545)
    private let soft = Color(hex: 0x544E70)

    var body: some View {
        ZStack {
            KlioMeshBg()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Прогресс").font(.system(size: 30, weight: .heavy)).foregroundStyle(ink)
                        Text("Серии и история по целям").font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
                    }
                    .padding(.top, 8)
                    weekCard
                    statsRow
                    if !goals.isEmpty {
                        Text("ИСТОРИЯ ПО ЦЕЛЯМ")
                            .font(.system(size: 11, weight: .heavy)).tracking(1.3).foregroundStyle(soft)
                            .padding(.leading, 4).padding(.top, 4)
                        VStack(spacing: 12) { ForEach(goals) { goalCard($0) } }
                    }
                    Spacer(minLength: 130)
                }
                .padding(.horizontal, 18)
                .klioReadable()
            }
            .scrollIndicators(.hidden)
        }
        .task {
            if Demo.enabled { vm.loadDemo() } else { await vm.load(token: session.token) }
            await loadHistories()
        }
    }

    // MARK: Week bar widget

    private var weekCard: some View {
        let week = weeklyRatios()
        let pct = week.isEmpty ? 0 : Int((week.reduce(0, +) / Double(week.count) * 100).rounded())
        let labels = weekdayLabels()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Неделя").font(.system(size: 14, weight: .heavy)).foregroundStyle(ink)
                Spacer()
                Text(String(format: L("%lld%% выполнено"), pct)).font(.system(size: 13, weight: .semibold)).foregroundStyle(soft)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let r = i < week.count ? week[i] : 0
                    VStack(spacing: 7) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(hex: 0x786EAA).opacity(0.1)).frame(height: 70)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: 0xFF9ECF), Color(hex: 0xB69CF0)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(8, 70 * r))
                        }
                        .frame(height: 70)
                        Text(LocalizedStringKey(labels[i])).font(.system(size: 11, weight: .semibold)).foregroundStyle(soft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16).klioGlass(26)
    }

    // MARK: Overall stats

    private var statsRow: some View {
        let totalDone = history.values.flatMap { $0 }.filter { $0.completed }.count
        let best = goals.map { $0.currentStreak }.max() ?? 0
        return HStack(spacing: 12) {
            statTile("\(totalDone)", "выполнено", "checkmark.seal.fill", Color(hex: 0x3FBFA8))
            statTile("\(best)", "серия", "flame.fill", Color(hex: 0xFF7EB3))
            statTile("\(goals.count)", "целей", "target", Color(hex: 0x8A7BFF))
        }
    }

    private func statTile(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(ink)
            Text(LocalizedStringKey(label)).font(.system(size: 11, weight: .semibold)).foregroundStyle(soft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).klioGlass(22)
    }

    // MARK: Per-goal history (grid, not a chart)

    private func goalCard(_ g: GoalCheckInItem) -> some View {
        let color = ac(g)
        let pts = history[g.goalId] ?? []
        let rate = pts.isEmpty ? 0 : Int((Double(pts.filter { $0.completed }.count) / Double(pts.count) * 100).rounded())
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: iconFor3(g)).font(.system(size: 17, weight: .medium)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title).font(.system(size: 16, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                    Text(String(format: L("за %lld дней · %lld%% выполнено"), window, rate)).font(.system(size: 12, weight: .medium)).foregroundStyle(soft)
                }
                Spacer(minLength: 6)
                if g.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.system(size: 11))
                        Text("\(g.currentStreak)").font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(color.opacity(0.12)).clipShape(Capsule())
                }
            }
            historyGrid(g, color: color)
        }
        .padding(16).klioGlass(24)
    }

    private let weeks = 5
    private let wdHeader = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    // Календарь по дням недели: колонки = Пн..Вс, последняя строка — текущая неделя.
    // Видно, в какой именно день цель выполнена (✓), пропущена (точка) или ещё не наступила.
    private func historyGrid(_ g: GoalCheckInItem, color: Color) -> some View {
        let cells = calendarCells(g) // weeks*7, индекс todayFlat = сегодня
        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { c in
                    Text(LocalizedStringKey(wdHeader[c])).font(.system(size: 10, weight: .bold)).foregroundStyle(soft)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<weeks, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        let st = cells[idx].0
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(cellColor(st, color))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(cellMark(st))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(cells[idx].1 ? color : .clear, lineWidth: 2)
                            )
                    }
                }
            }
        }
    }

    // Возвращает (состояние, isToday) для weeks*7 клеток, выровненных по дням недели.
    private func calendarCells(_ g: GoalCheckInItem) -> [(Cell, Bool)] {
        let hist = history[g.goalId] ?? []
        let wd = Calendar.current.component(.weekday, from: Date())
        let todayCol = (wd + 5) % 7 // Пн=0..Вс=6
        let todayFlat = (weeks - 1) * 7 + todayCol
        return (0..<weeks * 7).map { j in
            let daysAgo = todayFlat - j
            if daysAgo < 0 { return (.pad, false) } // будущее
            let idx = hist.count - 1 - daysAgo
            if idx < 0 { return (.none, false) }    // данных ещё нет
            return (hist[idx].completed ? .done : .miss, daysAgo == 0)
        }
    }

    private enum Cell { case done, miss, none, pad }
    private func cellColor(_ c: Cell, _ color: Color) -> Color {
        switch c {
        case .done: return color
        case .miss: return Color(hex: 0x786EAA).opacity(0.14)
        case .none: return color.opacity(0.10)
        case .pad: return .clear
        }
    }
    @ViewBuilder
    private func cellMark(_ c: Cell) -> some View {
        switch c {
        case .done: Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
        case .miss: Circle().fill(Color(hex: 0x786EAA).opacity(0.4)).frame(width: 4, height: 4)
        default: EmptyView()
        }
    }
    // MARK: Data helpers

    private func iconFor3(_ g: GoalCheckInItem) -> String {
        g.icon ?? ((g.kind == .quantDown && (g.todayTarget ?? 0) == 0) ? "nosign" : iconFor(g.title))
    }
    // Доля выполненных целей по дням за последние 7 дней (по выравненным хвостам историй).
    private func weeklyRatios() -> [Double] {
        let series = goals.compactMap { history[$0.goalId] }.map { Array($0.suffix(7)) }.filter { $0.count == 7 }
        guard !series.isEmpty else { return Array(repeating: 0, count: 7) }
        return (0..<7).map { p in
            let done = series.filter { $0[p].completed }.count
            return Double(done) / Double(series.count)
        }
    }
    private func weekdayLabels() -> [String] {
        let names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] // по weekday 1..7
        let cal = Calendar.current
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: -(6 - i), to: Date()) ?? Date()
            let wd = cal.component(.weekday, from: d) // 1=вс
            return names[(wd - 1) % 7]
        }
    }
    private func loadHistories() async {
        if Demo.enabled { for g in goals { history[g.goalId] = Demo.history(days: window) }; return }
        for g in goals {
            if let h: [HistoryPoint] = try? await APIClient.shared.request("goals/\(g.goalId)/history?days=\(window)", token: session.token) {
                history[g.goalId] = h
            }
        }
    }
}
