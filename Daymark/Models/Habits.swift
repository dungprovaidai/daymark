import Foundation
import SwiftData

enum HabitFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly target"
        case .monthly: return "Monthly target"
        case .custom: return "Selected days"
        }
    }
    var explanation: String {
        switch self {
        case .daily: return "A gentle check-in every day."
        case .weekly: return "Reach your target on any days this week."
        case .monthly: return "Reach your target across the month."
        case .custom: return "Only the weekdays you choose."
        }
    }
}

enum HabitKind: String, Codable, CaseIterable, Identifiable {
    case checkmark, counter, duration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .checkmark: return "Check-in"
        case .counter: return "Counter"
        case .duration: return "Duration"
        }
    }
    var icon: String {
        switch self {
        case .checkmark: return "checkmark.circle"
        case .counter: return "number"
        case .duration: return "timer"
        }
    }
}

@Model final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var details: String
    var icon: String
    var color: String
    var kindRaw: String
    var target: Double
    var step: Double
    var unit: String
    var frequencyRaw: String
    /// Calendar weekday numbers (Sunday = 1 ... Saturday = 7) for custom schedules.
    var weekdays: [Int]
    /// Number of completed days needed in a week or month.
    var periodTarget: Int
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var startDate: Date
    var endDate: Date?
    var archived: Bool
    var position: Int
    var createdAt: Date
    var updatedAt: Date

    var kind: HabitKind { HabitKind(rawValue: kindRaw) ?? .checkmark }
    var frequency: HabitFrequency { HabitFrequency(rawValue: frequencyRaw) ?? .daily }

    init(name: String, icon: String = "leaf", color: String = "mint") {
        id = UUID()
        self.name = name
        details = ""
        self.icon = icon
        self.color = color
        kindRaw = HabitKind.checkmark.rawValue
        target = 1
        step = 1
        unit = ""
        frequencyRaw = HabitFrequency.daily.rawValue
        weekdays = [2, 3, 4, 5, 6, 7, 1]
        periodTarget = 1
        reminderEnabled = false
        reminderHour = 9
        reminderMinute = 0
        startDate = Calendar.current.startOfDay(for: .now)
        endDate = nil
        archived = false
        position = 0
        createdAt = .now
        updatedAt = .now
    }

    var frequencyDescription: String {
        switch frequency {
        case .daily: return kind == .checkmark ? "Every day" : "Every day · \(target.compact) \(unit)".trimmingCharacters(in: .whitespaces)
        case .weekly: return "\(periodTarget)× each week"
        case .monthly: return "\(periodTarget)× each month"
        case .custom:
            let names = Calendar.current.veryShortStandaloneWeekdaySymbols
            let selected = weekdays.sorted().compactMap { day -> String? in
                let index = max(0, min(6, day - 1))
                return names.indices.contains(index) ? names[index] : nil
            }
            return selected.isEmpty ? "Selected days" : selected.joined(separator: " ")
        }
    }

    var targetDescription: String {
        switch kind {
        case .checkmark: return "One check-in"
        case .counter: return "\(target.compact) \(unit)".trimmingCharacters(in: .whitespaces)
        case .duration: return "\(target.compact) \(unit.isEmpty ? "minutes" : unit)".trimmingCharacters(in: .whitespaces)
        }
    }
}

@Model final class HabitCompletion {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var habitID: UUID
    var dayKey: String
    var date: Date
    var value: Double
    var completed: Bool
    var updatedAt: Date

    init(habitID: UUID, date: Date) {
        id = UUID()
        self.habitID = habitID
        self.date = Calendar.current.startOfDay(for: date)
        dayKey = DayKey.string(date)
        key = "\(habitID.uuidString)/\(DayKey.string(date))"
        value = 0
        completed = false
        updatedAt = .now
    }
}

struct HabitStats: Equatable {
    var currentStreak = 0
    var longestStreak = 0
    var completionRate = 0.0
    var totalCompletions = 0
    var periodProgress = 0
    var periodTarget = 1
    var periodLabel = ""
    var scheduledToday = false
    var completedToday = false
    var todayValue = 0.0
    var todayTarget = 1.0
}
