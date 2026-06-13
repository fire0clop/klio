import Foundation

// MARK: - Auth
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}

// MARK: - Profile
struct ProfileResponse: Codable {
    var name: String?
    var dateOfBirth: String?
    var gender: String?
    var heightCm: Double?
    var weightKg: Double?
    var onboardingCompleted: Bool
}

// MARK: - Goals
struct GoalStartResponse: Decodable {
    let goalId: UUID
    let question: String
    let questionIndex: Int
    let summary: String?
}

struct GoalAnswerResponse: Decodable {
    let done: Bool
    let question: String?
    let questionIndex: Int?
    let summary: String?
}

struct GoalMetric: Decodable, Identifiable {
    let id: UUID
    let metricName: String
    let unit: String
    let prompt: String
}

struct EffectMilestone: Decodable {
    let day: Int
    let percent: Int
    let description: String
}

struct Effect: Decodable {
    let name: String
    let icon: String
    let milestones: [EffectMilestone]
}

struct EffectTrajectory: Decodable {
    let effects: [Effect]
}

struct GoalResponse: Decodable, Identifiable {
    let id: UUID
    let title: String
    let goalType: String
    let frequencyType: String
    let dialogComplete: Bool
    let startedAt: String
    let isActive: Bool
    let currentStreak: Int
    let completionRate: Double
    let metrics: [GoalMetric]
}

// MARK: - Check-in
struct MetricItem: Decodable, Identifiable {
    let goalMetricId: UUID
    let metricName: String
    let unit: String
    let prompt: String
    let valueToday: String?

    var id: UUID { goalMetricId }
}

struct PlanStepInfo: Decodable {
    let dayNumber: Int
    let limit: Double?
    let unit: String?
}

struct GoalSuggestion: Decodable {
    let kind: String            // raise | switch_metric
    let suggestedTarget: Double?
    let unit: String?
    let message: String
}

struct GoalCheckInItem: Decodable, Identifiable {
    let goalId: UUID
    let title: String
    let goalType: String        // binary | quantitative
    let frequencyType: String
    let suggestion: GoalSuggestion?
    let direction: String?      // up | down | target
    let controllability: String?// direct | indirect
    let unit: String?
    let baseline: Double?
    let target: Double?
    let currentStreak: Int
    let completedToday: Bool?
    let confirmedToday: Bool?
    let actualValueToday: Double?
    let note: String?
    let plan: PlanStepInfo?
    let metrics: [MetricItem]
    var icon: String? = nil   // SF Symbol, выбранный ИИ при создании цели

    var id: UUID { goalId }

    // MARK: Derived UI type
    enum Kind { case fact, quantUp, quantDown, valueLog }

    var kind: Kind {
        if controllability == "indirect" || direction == "target" { return .valueLog }
        if goalType == "quantitative" {
            return direction == "up" ? .quantUp : .quantDown
        }
        return .fact
    }

    /// Цель на сегодня (число) — из плана или target.
    var todayTarget: Double? { plan?.limit ?? target }
    var displayUnit: String { plan?.unit ?? unit ?? "" }
}

struct DailyLogData: Codable {
    var weightKg: Double?
    var sleepHours: Double?
    var energy: Int?
    var mood: Int?
}

struct CheckInTodayResponse: Decodable {
    let date: String
    let goals: [GoalCheckInItem]
    let dailyLog: DailyLogData?
    let allDone: Bool
}

// MARK: - Analytics
struct StreakResponse: Decodable {
    let goalId: UUID
    let currentStreak: Int
    let bestStreak: Int
    let totalCompleted: Int
    let weeklyRate: Double
    let monthlyRate: Double
    let quarterlyRate: Double
}

struct EffectProgress: Decodable, Identifiable {
    let name: String
    let icon: String
    let currentPercent: Int
    let description: String

    var id: String { name }
}

struct GoalEffectsResponse: Decodable {
    let goalId: UUID
    let title: String
    let currentStreak: Int
    let effects: [EffectProgress]
}

struct TimelineEntry: Decodable {
    let date: String
    let completed: Bool?
    let isPlanned: Bool
}

struct GoalTimelineResponse: Decodable {
    let goalId: UUID
    let entries: [TimelineEntry]
}

struct DailyLogPoint: Decodable {
    let date: String
    let weightKg: Double?
    let sleepHours: Double?
    let energy: Int?
    let mood: Int?
}

struct DailyLogTimelineResponse: Decodable {
    let entries: [DailyLogPoint]
}

struct HistoryPoint: Decodable, Identifiable {
    let date: String
    let completed: Bool
    let value: Double?
    var id: String { date }
}

struct InsightResponse: Decodable, Identifiable {
    let id: UUID
    let content: String
    var kind: String? = nil
    var title: String? = nil
    let generatedAt: String
}

struct SphereResponse: Decodable, Identifiable {
    let icon: String
    let name: String
    let percent: Int
    let goals: [String]
    var caption: String = ""
    var id: String { icon }
}
