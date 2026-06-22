import SwiftUI

// MARK: - View model

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var checkin: CheckInTodayResponse?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var justSaved = false

    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    @Published var completions: [UUID: Bool] = [:]
    @Published var confirmed: [UUID: Bool] = [:]
    @Published var actualValues: [UUID: String] = [:]
    @Published var notes: [UUID: String] = [:]
    @Published var dailyLog = DailyLogData()
    @Published var weightStr = ""
    @Published var sleepStr = ""

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    var isReadOnly: Bool { selectedDate < Calendar.current.startOfDay(for: Date()) }
    var doneCount: Int { completions.values.filter { $0 }.count }
    var totalCount: Int { checkin?.goals.count ?? 0 }
    var allDone: Bool { totalCount > 0 && doneCount == totalCount }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    func selectDate(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: Date())
        guard day <= today else { return }
        selectedDate = day
    }

    func selectPrev() {
        guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = prev
    }

    func selectNext() {
        let today = Calendar.current.startOfDay(for: Date())
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate),
              next <= today else { return }
        selectedDate = next
    }

    func load(token: String) async {
        isLoading = true
        let path = isToday ? "checkin/today" : "checkin/\(dateString)"
        do {
            let resp: CheckInTodayResponse = try await APIClient.shared.request(path, token: token)
            checkin = resp
            completions = [:]; confirmed = [:]; actualValues = [:]; notes = [:]
            for goal in resp.goals {
                completions[goal.goalId] = goal.completedToday ?? false
                confirmed[goal.goalId] = goal.confirmedToday ?? false
                if goal.goalType == "quantitative", let v = goal.actualValueToday {
                    actualValues[goal.goalId] = v.clean
                }
                notes[goal.goalId] = goal.note ?? ""
            }
            if let log = resp.dailyLog {
                dailyLog = log
                weightStr = log.weightKg.map { $0.clean } ?? ""
                sleepStr  = log.sleepHours.map { $0.clean } ?? ""
            } else {
                dailyLog = DailyLogData(); weightStr = ""; sleepStr = ""
            }
        } catch {}
        isLoading = false
    }

    func save(token: String) async {
        guard let checkin, !isReadOnly else { return }
        isSaving = true
        dailyLog.weightKg   = weightStr.decimalDouble
        dailyLog.sleepHours = sleepStr.decimalDouble

        struct EntryInput: Encodable {
            let goalId: UUID; let completed: Bool
            let actualValue: Double?; let note: String?
        }
        struct Body: Encodable { let date: String; let entries: [EntryInput]; let dailyLog: DailyLogData }

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
                actualValue: goal.goalType == "quantitative" ? actualVal : nil,
                note: notes[goal.goalId]
            )
        }

        try? await APIClient.shared.requestEmpty(
            "checkin", method: "POST",
            body: Body(date: dateString, entries: entries, dailyLog: dailyLog),
            token: token
        )
        isSaving = false
        withAnimation { justSaved = true }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        withAnimation { justSaved = false }
    }
}

// MARK: - Number helpers

extension Double {
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }
}

extension String {
    /// Parses a user-entered decimal string, accepting both `,` and `.` as separators.
    /// Russian iOS keyboards default to `,` on the decimal pad, which Swift's `Double()` rejects.
    var decimalDouble: Double? {
        let normalized = replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
