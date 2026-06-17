import Foundation

// Демо-данные только для съёмки скриншотов (активируется флагом запуска / env-переменной).
// Пользовательского входа в демо нет.

enum Demo {
    static func flag(_ arg: String, _ env: String) -> Bool {
        CommandLine.arguments.contains(arg) || ProcessInfo.processInfo.environment[env] == "1"
    }
    static var enabled: Bool { flag("--demo", "KLIO_DEMO") }
    static var startReflect: Bool { flag("--reflect", "KLIO_REFLECT") }
    static var openAnalytics: Bool { flag("--analytics", "KLIO_ANALYTICS") }
    static var openCreate: Bool { flag("--create", "KLIO_CREATE") }

    /// Локализованный выбор демо-строки по текущему языку приложения (для скриншотов).
    static func dl(_ ru: String, _ en: String, _ es: String) -> String {
        switch LocaleManager.shared.language {
        case .ru: return ru
        case .en: return en
        case .es: return es
        }
    }

    static func profile() -> ProfileResponse {
        ProfileResponse(name: "Demo User", dateOfBirth: "1995-01-01", gender: "male",
                        heightCm: 180, weightKg: 78, onboardingCompleted: true)
    }

    static func goals() -> [GoalCheckInItem] {
        let uPages = dl("стр", "pg", "pág")
        let uL = dl("л", "L", "L")
        let uCups = dl("чаш", "cups", "tazas")
        let uKg = dl("кг", "kg", "kg")
        return [
            GoalCheckInItem(
                goalId: UUID(), title: dl("Зарядка", "Workout", "Ejercicio"), goalType: "binary",
                frequencyType: "daily", suggestion: nil, direction: nil, controllability: nil,
                unit: nil, baseline: nil, target: nil, currentStreak: 14,
                completedToday: true, confirmedToday: false, actualValueToday: nil,
                note: nil, plan: nil, metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: dl("Читать", "Read", "Leer"), goalType: "quantitative", frequencyType: "daily",
                suggestion: nil, direction: "up", controllability: "direct", unit: uPages,
                baseline: 30, target: 100, currentStreak: 21,
                completedToday: false, confirmedToday: false, actualValueToday: 80,
                note: nil, plan: PlanStepInfo(dayNumber: 21, limit: 100, unit: uPages), metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: dl("Вода", "Water", "Agua"), goalType: "quantitative", frequencyType: "daily",
                suggestion: nil, direction: "up", controllability: "direct", unit: uL,
                baseline: 0, target: 2, currentStreak: 4,
                completedToday: false, confirmedToday: false, actualValueToday: 1.2,
                note: nil, plan: PlanStepInfo(dayNumber: 4, limit: 2, unit: uL), metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: dl("Не курить", "No smoking", "No fumar"), goalType: "quantitative", frequencyType: "daily",
                suggestion: nil, direction: "down", controllability: "direct", unit: "",
                baseline: 0, target: 0, currentStreak: 8,
                completedToday: false, confirmedToday: false, actualValueToday: nil,
                note: nil, plan: PlanStepInfo(dayNumber: 8, limit: 0, unit: ""), metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: dl("Кофе", "Coffee", "Café"), goalType: "quantitative", frequencyType: "daily",
                suggestion: nil, direction: "down", controllability: "direct", unit: uCups,
                baseline: 4, target: 2, currentStreak: 3,
                completedToday: false, confirmedToday: false, actualValueToday: 1,
                note: nil, plan: PlanStepInfo(dayNumber: 3, limit: 2, unit: uCups), metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: dl("Вес", "Weight", "Peso"), goalType: "quantitative", frequencyType: "daily",
                suggestion: nil, direction: "target", controllability: "indirect", unit: uKg,
                baseline: 88, target: 75, currentStreak: 0,
                completedToday: nil, confirmedToday: false, actualValueToday: 84.2,
                note: nil, plan: nil, metrics: []),
        ]
    }

    static func goalsOld() -> [GoalCheckInItem] {
        [
            GoalCheckInItem(
                goalId: UUID(), title: "Зарядка по утрам", goalType: "binary",
                frequencyType: "daily", suggestion: nil, direction: nil, controllability: nil,
                unit: nil, baseline: nil, target: nil, currentStreak: 14,
                completedToday: true, confirmedToday: false, actualValueToday: nil,
                note: nil, plan: nil, metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: "Читать", goalType: "quantitative",
                frequencyType: "daily",
                suggestion: GoalSuggestion(
                    kind: "raise", suggestedTarget: 130, unit: "страниц",
                    message: "Ты стабильно перевыполняешь: ~125 страниц при цели 100. Поднять цель до 130?"),
                direction: "up", controllability: "direct", unit: "страниц",
                baseline: 30, target: 100, currentStreak: 21,
                completedToday: false, confirmedToday: false, actualValueToday: 80,
                note: nil, plan: PlanStepInfo(dayNumber: 21, limit: 100, unit: "страниц"), metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: "Не курить", goalType: "quantitative",
                frequencyType: "daily", suggestion: nil, direction: "down", controllability: "direct",
                unit: "сигарет", baseline: 20, target: 5, currentStreak: 8,
                completedToday: true, confirmedToday: true, actualValueToday: 3,
                note: nil, plan: PlanStepInfo(dayNumber: 8, limit: 5, unit: "сигарет"), metrics: []),
            GoalCheckInItem(
                goalId: UUID(), title: "Вес", goalType: "quantitative",
                frequencyType: "daily", suggestion: nil, direction: "target", controllability: "indirect",
                unit: "кг", baseline: 88, target: 75, currentStreak: 0,
                completedToday: nil, confirmedToday: false, actualValueToday: 84.2,
                note: nil, plan: nil, metrics: []),
        ]
    }

    static func insights() -> [InsightResponse] {
        [
            InsightResponse(id: UUID(),
                content: dl("Вчера закрыл 4 из 5 — упустил только воду. Зарядка и чтение снова на месте, серия держится.",
                            "You closed 4 of 5 yesterday — only water slipped. Workout and reading are back, the streak holds.",
                            "Ayer cerraste 4 de 5 — solo se escapó el agua. Ejercicio y lectura de vuelta, la racha aguanta."),
                kind: "reaction", title: dl("Вчера почти идеально", "Almost a perfect day", "Casi un día perfecto"), generatedAt: "2026-06-23"),
            InsightResponse(id: UUID(),
                content: dl("Чтение растёт: +20 страниц в день за две недели. Скоро предложу поднять планку.",
                            "Reading is climbing: +20 pages a day over two weeks. Soon I'll suggest raising the bar.",
                            "La lectura sube: +20 páginas al día en dos semanas. Pronto sugeriré subir el listón."),
                kind: "win", title: dl("Чтение в гору", "Reading on the rise", "Lectura en ascenso"), generatedAt: "2026-06-23"),
            InsightResponse(id: UUID(),
                content: dl("Вода проседает третий день подряд — стакан утром закроет половину нормы.",
                            "Water has dipped three days running — a glass in the morning covers half your goal.",
                            "El agua baja tres días seguidos — un vaso por la mañana cubre la mitad de tu meta."),
                kind: "watch", title: dl("Вода буксует", "Water is stalling", "El agua se atasca"), generatedAt: "2026-06-23"),
            InsightResponse(id: UUID(),
                content: dl("Сегодня среда — твой самый сильный день за месяц. Лови момент и закрой всё до вечера.",
                            "It's Wednesday — your strongest day this month. Seize it and close everything by evening.",
                            "Es miércoles — tu día más fuerte del mes. Aprovéchalo y cierra todo antes de la noche."),
                kind: "tip", title: dl("Совет на сегодня", "Tip for today", "Consejo de hoy"), generatedAt: "2026-06-23"),
        ]
    }

    static func spheres() -> [SphereResponse] {
        let gRead = dl("Читать", "Read", "Leer")
        let gWorkout = dl("Зарядка", "Workout", "Ejercicio")
        let gWater = dl("Вода", "Water", "Agua")
        let gSmoke = dl("Не курить", "No smoking", "No fumar")
        return [
            SphereResponse(icon: "brain", name: dl("Начитанность", "Literacy", "Cultura"), percent: 82,
                goals: [gRead], caption: dl("Словарный запас и фокус заметно растут", "Vocabulary and focus are clearly growing", "El vocabulario y el enfoque crecen")),
            SphereResponse(icon: "energy", name: dl("Энергия", "Energy", "Energía"), percent: 75,
                goals: [gWorkout, gWater], caption: dl("Бодрее по утрам, меньше спадов днём", "Brighter mornings, fewer afternoon dips", "Mañanas con más energía, menos bajones")),
            SphereResponse(icon: "mood", name: dl("Настроение", "Mood", "Ánimo"), percent: 67,
                goals: [gWorkout], caption: dl("Ровнее в течение дня", "Steadier through the day", "Más estable durante el día")),
            SphereResponse(icon: "lungs", name: dl("Лёгкие", "Lungs", "Pulmones"), percent: 61,
                goals: [gSmoke], caption: dl("Дыхание свободнее, кашель реже", "Breathing easier, less coughing", "Respiras mejor, menos tos")),
            SphereResponse(icon: "heart", name: dl("Сердце", "Heart", "Corazón"), percent: 55,
                goals: [gSmoke, gWorkout], caption: dl("Пульс покоя понемногу снижается", "Resting heart rate is easing down", "El pulso en reposo baja poco a poco")),
        ]
    }

    static func history(days: Int = 14) -> [HistoryPoint] {
        (0..<days).map { i in
            let fromEnd = days - 1 - i // 0 = сегодня
            let done = fromEnd == 0 ? false : (fromEnd % 6 != 0) // сегодня по живому; редкие пропуски
            return HistoryPoint(date: "2026-06-\(i + 1)", completed: done, value: nil)
        }
    }
}

extension DashboardViewModel {
    func loadDemo() {
        let g = Demo.goals()
        checkin = CheckInTodayResponse(date: "2026-06-13", goals: g, dailyLog: nil, allDone: false)
        completions = [:]; confirmed = [:]; actualValues = [:]; notes = [:]
        for goal in g {
            completions[goal.goalId] = goal.completedToday ?? false
            confirmed[goal.goalId] = goal.confirmedToday ?? false
            if let v = goal.actualValueToday { actualValues[goal.goalId] = v.clean }
        }
        dailyLog.mood = 4
        dailyLog.energy = 4
        isLoading = false
    }
}
