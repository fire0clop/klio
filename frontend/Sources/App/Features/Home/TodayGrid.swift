import SwiftUI

// v2 «Сегодня»: сетка плиток (в духе Streaks) на реальных данных + свой числовой кейпад.

struct TodayGrid: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var vm: DashboardViewModel
    var onCreate: () -> Void

    @State private var editing: UUID?
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Klio.bg, Color(hex: 0xEFE8DB)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            if vm.isLoading && vm.checkin == nil {
                ProgressView().tint(Klio.accent)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(vm.checkin?.goals ?? []) { tile($0) }
                        }
                        Spacer(minLength: 104)
                    }
                    .padding(.horizontal, 18).padding(.top, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(item: Binding(get: { editing.flatMap { id in (vm.checkin?.goals ?? []).first { $0.id == id } } },
                             set: { _ in editing = nil })) { goal in
            KeypadSheet(
                title: goal.title, unit: goal.displayUnit, kind: goal.kind, target: goal.todayTarget,
                text: Binding(get: { vm.actualValues[goal.goalId] ?? "" },
                              set: { vm.actualValues[goal.goalId] = $0 }),
                onDone: { editing = nil; commit() }
            )
            .presentationDetents([.height(540)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var header: some View {
        let goals = vm.checkin?.goals ?? []
        let total = goals.filter { $0.kind != .valueLog }.count
        let done = goals.filter { $0.kind != .valueLog && isDone($0) }.count
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLine.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(Klio.inkFaint)
                Text("Сегодня").font(.system(size: 32, weight: .bold)).foregroundStyle(Klio.ink)
            }
            Spacer()
            ZStack {
                Circle().stroke(Klio.sunken, lineWidth: 6).frame(width: 50, height: 50)
                Circle().trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                    .stroke(Klio.gradient(0), style: .init(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 50, height: 50)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: done)
                Text("\(done)/\(total)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Klio.ink)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Tile

    private func tile(_ goal: GoalCheckInItem) -> some View {
        let v = actual(goal)
        let t = goal.todayTarget ?? 0
        let over = goal.kind == .quantDown && t > 0 && v > t
        let complete = (goal.kind == .fact && isDone(goal)) || (goal.kind == .quantUp && t > 0 && v >= t)
        let frac: Double = {
            switch goal.kind {
            case .fact: return isDone(goal) ? 1 : 0
            case .quantUp, .quantDown: return t > 0 ? min(v / t, 1) : 0
            case .valueLog: return 0
            }
        }()
        return Button {
            if goal.kind == .fact { toggleFact(goal) } else { editing = goal.id }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Klio.sunken, lineWidth: 7).frame(width: 86, height: 86)
                    Circle().trim(from: 0, to: max(0.0001, frac))
                        .stroke(over ? AnyShapeStyle(Klio.over) : (complete ? AnyShapeStyle(Klio.done) : AnyShapeStyle(Klio.gradient(0))),
                                style: .init(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 86, height: 86)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: frac)
                    center(goal, complete: complete)
                }
                Text(goal.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Klio.ink).lineLimit(1)
                if goal.currentStreak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 10))
                        Text("\(goal.currentStreak)").font(.system(size: 12, weight: .bold))
                    }.foregroundStyle(Klio.accent.opacity(0.85))
                } else {
                    Text(" ").font(.system(size: 12))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(Klio.surface)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: Klio.ink.opacity(0.07), radius: 14, y: 6)
        }
        .buttonStyle(TilePress())
    }

    @ViewBuilder
    private func center(_ g: GoalCheckInItem, complete: Bool) -> some View {
        switch g.kind {
        case .fact:
            if isDone(g) { Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(Klio.done) }
            else { Image(systemName: iconFor(g.title)).font(.system(size: 26)).foregroundStyle(Klio.accent) }
        case .quantUp, .quantDown:
            VStack(spacing: -2) {
                Text(actual(g).cl).font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(complete ? Klio.done : Klio.ink)
                if let t = g.todayTarget {
                    Text(g.kind == .quantDown ? "≤\(t.cl)" : "/\(t.cl)")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Klio.inkSoft)
                }
            }
        case .valueLog:
            VStack(spacing: -2) {
                Text((g.actualValueToday ?? actual(g)).cl).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Klio.ink)
                Text(g.displayUnit).font(.system(size: 11, weight: .medium)).foregroundStyle(Klio.inkSoft)
            }
        }
    }

    // MARK: Logic

    private var dateLine: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }
    private func actual(_ g: GoalCheckInItem) -> Double { vm.actualValues[g.goalId]?.decimalDouble ?? 0 }
    private func isDone(_ g: GoalCheckInItem) -> Bool {
        switch g.kind {
        case .fact: return vm.completions[g.goalId] ?? false
        case .quantUp: guard let t = g.todayTarget, t > 0 else { return false }; return actual(g) >= t
        case .quantDown: guard let t = g.todayTarget else { return false }; return vm.actualValues[g.goalId] != nil && actual(g) <= t
        case .valueLog: return false
        }
    }
    private func toggleFact(_ g: GoalCheckInItem) {
        let cur = vm.completions[g.goalId] ?? false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { vm.completions[g.goalId] = !cur }
        Haptic.tap(cur ? .light : .medium)
        commit()
    }
    private func commit() { Task { await vm.commitNow(token: session.token) } }
}

// MARK: - Tile press

struct TilePress: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Icon heuristic

func iconFor(_ title: String) -> String {
    let t = title.lowercased()
    if t.contains("заряд") || t.contains("трен") || t.contains("спорт") || t.contains("отжим") { return "figure.run" }
    if t.contains("бег") { return "figure.run" }
    if t.contains("чита") || t.contains("книг") { return "book.fill" }
    if t.contains("вод") || t.contains("пить") { return "drop.fill" }
    if t.contains("кур") || t.contains("сигар") || t.contains("вейп") { return "nosign" }
    if t.contains("вес") || t.contains("худе") { return "scalemass.fill" }
    if t.contains("медит") { return "leaf.fill" }
    if t.contains("сон") || t.contains("спать") { return "bed.double.fill" }
    if t.contains("шаг") { return "figure.walk" }
    if t.contains("телефон") || t.contains("экран") || t.contains("соцсет") { return "iphone" }
    if t.contains("англ") || t.contains("язык") || t.contains("учи") { return "character.book.closed.fill" }
    if t.contains("ден") || t.contains("эконом") || t.contains("трат") { return "rublesign.circle.fill" }
    return "target"
}

// MARK: - Custom numeric keypad

// Концептуальный кейпад: тинт-фон в цвет цели, БЕЗ белых клавиш-рамок —
// крупные «парящие» цифры, кольцевой индикатор прогресса вокруг значения,
// круглая кнопка-галочка вместо полосы «Готово».
struct KeypadSheet: View {
    let title: String
    let unit: String
    let kind: GoalCheckInItem.Kind
    let target: Double?
    var tint: Color = Klio.bg
    @Binding var text: String
    var onDone: () -> Void

    @State private var entry: String = ""
    @State private var pressed: String?

    private var current: Double { Double(entry) ?? (text.decimalDouble ?? 0) }
    private var ringFrac: Double { guard let t = target, t > 0 else { return 0 }; return min(current / t, 1) }

    var body: some View {
        VStack(spacing: 22) {
            // значение в кольце-прогрессе
            ZStack {
                Circle().stroke(Klio.ink.opacity(0.06), lineWidth: 7).frame(width: 150, height: 150)
                if target != nil {
                    Circle().trim(from: 0, to: ringFrac)
                        .stroke(Klio.gradient(0), style: .init(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: ringFrac)
                }
                VStack(spacing: 0) {
                    Text(entry.isEmpty ? current.cl : entry)
                        .font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Klio.ink)
                        .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: 130)
                    Text(unit.isEmpty ? title : unit).font(.system(size: 13, weight: .medium)).foregroundStyle(Klio.inkSoft)
                }
            }
            .padding(.top, 18)

            if let t = target {
                Text(kind == .quantDown ? "лимит ≤ \(t.cl) \(unit)" : "цель \(t.cl) \(unit)")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Klio.inkSoft)
            }

            // быстрые шаги — текстом, без рамок
            HStack(spacing: 22) {
                ForEach(quickSteps, id: \.self) { s in
                    Button { entry = max(0, current + Double(s)).cl; Haptic.tap() } label: {
                        Text("+\(s)").font(.system(size: 16, weight: .bold)).foregroundStyle(Klio.accent)
                    }.buttonStyle(.plain)
                }
            }

            // клавиши — «парящие» цифры без фона; нижний ряд: точка, 0, стереть, принять
            VStack(spacing: 6) {
                ForEach([["1","2","3"],["4","5","6"],["7","8","9"]], id: \.self) { rowKeys in
                    HStack(spacing: 6) { ForEach(rowKeys, id: \.self) { key($0) } }
                }
                HStack(spacing: 6) {
                    key(".")
                    key("0")
                    key("⌫")
                    confirmKey
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.ignoresSafeArea())
    }

    // Кнопка «принять» — ячейка нижнего ряда рядом со «стереть», без перекрытия.
    private var confirmKey: some View {
        Button {
            if let v = Double(entry) { text = v.cl }
            Haptic.tap(.medium); onDone()
        } label: {
            Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 58)
                .background(Klio.gradient(0))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Klio.accent.opacity(0.35), radius: 8, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(TilePress())
    }

    private var quickSteps: [Int] {
        switch kind {
        case .quantDown: return [1, 5]
        case .quantUp: return (target ?? 0) >= 100 ? [10, 25] : [1, 5]
        default: return [1, 5]
        }
    }

    private func key(_ k: String) -> some View {
        Button {
            switch k {
            case "⌫": if !entry.isEmpty { entry.removeLast() }
            case ".": if !entry.contains(".") { entry += entry.isEmpty ? "0." : "." }
            default: entry += k
            }
            Haptic.tap()
        } label: {
            Group {
                if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 24, weight: .regular)) }
                else { Text(k).font(.system(size: 30, weight: .semibold, design: .rounded)) }
            }
            .foregroundStyle(Klio.ink)
            .frame(maxWidth: .infinity).frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePress())
    }
}

private extension Double {
    var cl: String { truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self) }
}
