import Foundation

extension DashboardViewModel {
    /// Сохраняет текущее состояние сразу, без анимации "сохранено" (для тап-коммита).
    func commitNow(token: String) async {
        guard let checkin, !isReadOnly else { return }
        dailyLog.weightKg = weightStr.decimalDouble
        dailyLog.sleepHours = sleepStr.decimalDouble

        struct EntryInput: Encodable {
            let goalId: UUID; let completed: Bool; let confirmed: Bool
            let actualValue: Double?; let note: String?
        }
        struct Body: Encodable { let date: String; let entries: [EntryInput]; let dailyLog: DailyLogData }

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let ds = f.string(from: selectedDate)

        let entries = checkin.goals.map { goal -> EntryInput in
            let actualVal = (actualValues[goal.goalId] ?? "").decimalDouble
            let completed: Bool
            if goal.goalType == "quantitative", let v = actualVal, let limit = goal.plan?.limit {
                completed = v <= limit
            } else {
                completed = completions[goal.goalId] ?? false
            }
            return EntryInput(
                goalId: goal.goalId,
                completed: completed,
                confirmed: confirmed[goal.goalId] ?? false,
                actualValue: goal.goalType == "quantitative" ? actualVal : nil,
                note: notes[goal.goalId]
            )
        }

        try? await APIClient.shared.requestEmpty(
            "checkin", method: "POST",
            body: Body(date: ds, entries: entries, dailyLog: dailyLog),
            token: token
        )
    }
}
