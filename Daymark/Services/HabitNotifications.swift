import Foundation
import UserNotifications

/// Habit reminders use repeating calendar triggers, so they remain useful while
/// the app is closed and do not need to be refreshed every time an event changes.
enum HabitNotificationScheduler {
    static let prefix = "daymark/habit/"

    static func sync(habits: [Habit]) {
        Task { await schedule(habits.filter { !$0.archived }) }
    }

    private static func schedule(_ habits: [Habit]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let today = Calendar.current.startOfDay(for: .now)
        var scheduled = 0

        for habit in habits.prefix(30) where habit.reminderEnabled {
            if let end = habit.endDate, Calendar.current.startOfDay(for: end) < today { continue }
            let hitComponents = reminderComponents(for: habit)
            for (index, components) in hitComponents.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = habit.name
                content.body = reminderBody(for: habit)
                content.sound = .default
                content.threadIdentifier = "habit-\(habit.id.uuidString)"
                content.userInfo = ["deepLink": "daymark://habits?habit=\(habit.id.uuidString)"]
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(prefix)\(habit.id.uuidString)/\(index)",
                    content: content,
                    trigger: trigger
                )
                do {
                    try await center.add(request)
                    scheduled += 1
                } catch { break }
                if scheduled >= 48 { return }
            }
        }
    }

    private static func reminderComponents(for habit: Habit) -> [DateComponents] {
        var base = DateComponents()
        base.hour = habit.reminderHour
        base.minute = habit.reminderMinute
        switch habit.frequency {
        case .daily:
            return [base]
        case .custom:
            let days = habit.weekdays.isEmpty ? [2] : habit.weekdays
            return days.map { day in
                var components = base; components.weekday = day; return components
            }
        case .weekly:
            let days = habit.weekdays.isEmpty ? [2] : habit.weekdays
            return Array(Set(days)).sorted().map { day in
                var components = base; components.weekday = day; return components
            }
        case .monthly:
            var components = base; components.day = 1; return [components]
        }
    }

    private static func reminderBody(for habit: Habit) -> String {
        switch habit.kind {
        case .checkmark: return "A small moment for \(habit.name)."
        case .counter: return "A gentle nudge toward \(habit.target.compact) \(habit.unit)."
        case .duration: return "A little time for \(habit.name) today."
        }
    }
}
