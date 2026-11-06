import Foundation
import Observation
import UserNotifications

struct PlannedNotification {
    let id: String
    let eventID: UUID
    let occurrence: Date
    let title: String
    let body: String
    let fireDate: Date
}

@MainActor @Observable final class NotificationCoordinator {
    var authorization: UNAuthorizationStatus = .notDetermined
    var queuedCount = 0
    var omittedCount = 0
    var lastScheduledDate: Date?
    var lastError: String?
    private var waiting: [PlannedNotification]?
    private var running = false
    private let center = UNUserNotificationCenter.current()
    /// Leave a little capacity below the platform's pending-request limit.
    static let capacity = 60
    static let testIdentifier = "daymark/test"

    var canDeliver: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var statusTitle: String {
        switch authorization {
        case .authorized: return "On"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporary"
        case .denied: return "Off"
        case .notDetermined: return "Not enabled"
        @unknown default: return "Unknown"
        }
    }

    func refreshPermission() async { authorization = await center.notificationSettings().authorizationStatus }

    /// Only the explicit button in the permission UI calls this. When the
    /// status is already determined, iOS will not show the dialog again, so we
    /// simply refresh instead of asking repeatedly.
    @discardableResult
    func requestPermission() async -> UNAuthorizationStatus {
        if authorization != .notDetermined {
            await refreshPermission()
            return authorization
        }
        do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { lastError = error.localizedDescription }
        await refreshPermission()
        return authorization
    }

    /// Schedules a real local notification in three seconds. Uses a stable
    /// identifier so repeated taps replace the previous test.
    func sendTestNotification() async -> String? {
        await refreshPermission()
        guard canDeliver else {
            return "Notifications are not allowed. Enable them in iOS Settings first."
        }
        let content = UNMutableNotificationContent()
        content.title = "Daymark reminder test"
        content.body = "If you can see this, notifications are working."
        content.sound = .default
        content.userInfo = ["deepLink": "daymark://today"]
        let request = UNNotificationRequest(
            identifier: Self.testIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        center.removePendingNotificationRequests(withIdentifiers: [Self.testIdentifier])
        do {
            try await center.add(request)
            lastError = nil
            return nil
        } catch {
            lastError = "The test notification could not be scheduled. \(error.localizedDescription)"
            return lastError
        }
    }
    func reconcile(events: [CalendarEvent], reminders: [Reminder], recurrences: [Recurrence], exceptions: [EventException]) {
        waiting = Self.makePlan(events: events, reminders: reminders, recurrences: recurrences, exceptions: exceptions)
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    static func makePlan(events: [CalendarEvent], reminders: [Reminder], recurrences: [Recurrence], exceptions: [EventException], now: Date = .now) -> [PlannedNotification] {
        let horizon = Calendar.current.date(byAdding: .year, value: 2, to: now)!
        let exceptionMap = Dictionary(uniqueKeysWithValues: exceptions.map { ($0.key, $0) })
        let rules = Dictionary(uniqueKeysWithValues: recurrences.map { ($0.eventID, $0.rule) })
        let remindersByEvent = Dictionary(grouping: reminders, by: \.eventID)
        var plan: [PlannedNotification] = []
        for event in events where !event.completed {
            let schedule = EventSchedule(start: event.start, end: event.end, allDay: event.allDay, timeZoneID: event.timeZoneID, rule: rules[event.id])
            let cal = RecurrenceEngine.calendar(for: schedule)
            for reminder in remindersByEvent[event.id] ?? [] {
                let spec = reminder.spec
                // Expand by each lead interval so reminders for later events are not lost.
                let searchEnd = cal.date(byAdding: spec.unit.component, value: spec.amount, to: horizon) ?? horizon
                let searchStart = cal.date(byAdding: spec.unit.component, value: spec.amount, to: now) ?? now
                let times: [OccurrenceTime]
                if schedule.rule == nil { times = [.init(start: event.start, end: event.end)] }
                else { times = RecurrenceEngine.occurrences(schedule, in: .init(start: searchStart, end: searchEnd)) }
                for time in times {
                    let key = OccurrenceIdentity.key(eventID: event.id, start: time.start)
                    let exception = exceptionMap[key]
                    guard exception?.cancelled != true, exception?.completed != true, exception?.replacementID == nil,
                          let fire = spec.fireDate(before: time.start, calendar: cal), fire > now else { continue }
                    let formatter = DateFormatter()
                    formatter.timeZone = cal.timeZone; formatter.dateStyle = .medium
                    formatter.timeStyle = event.allDay ? .none : .short
                    let when = event.allDay ? "All day · \(formatter.string(from: time.start))" : formatter.string(from: time.start)
                    let body = event.location.isEmpty ? when : "\(when) · \(event.location)"
                    plan.append(.init(id: "daymark/\(key)/\(reminder.id.uuidString)", eventID: event.id,
                                      occurrence: time.start, title: event.title, body: body, fireDate: fire))
                }
            }
        }
        return plan.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
    }

    private func drain() async {
        // Serial reconciliation: edits made during an await replace the waiting plan,
        // then run after the current pass, so an older pass cannot win a race.
        while let plan = waiting {
            waiting = nil
            await refreshPermission()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("daymark/") && !$0.identifier.hasPrefix(HabitNotificationScheduler.prefix) }.map(\.identifier))
            queuedCount = 0; omittedCount = 0; lastScheduledDate = nil; lastError = nil
            guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else { continue }
            let selected = Array(plan.prefix(Self.capacity))
            omittedCount = max(0, plan.count - selected.count)
            for item in selected {
                let content = UNMutableNotificationContent()
                content.title = item.title; content.body = item.body; content.sound = .default
                content.threadIdentifier = item.eventID.uuidString
                content.userInfo = ["eventID": item.eventID.uuidString, "start": item.occurrence.timeIntervalSince1970]
                var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
                var components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
                components.timeZone = utc.timeZone; components.calendar = utc
                let request = UNNotificationRequest(identifier: item.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                do {
                    try await center.add(request)
                    queuedCount += 1; lastScheduledDate = item.fireDate
                } catch { lastError = "Some reminders could not be scheduled: \(error.localizedDescription)" }
            }
        }
        running = false
    }
}

@MainActor @Observable final class AppRoute {
    static let shared = AppRoute()
    var selectedTab = 0
    var calendarDate = Date()
    var eventID: UUID?
    var journalID: UUID?
    var journalDate: Date?
    var focusedFieldID: UUID?
    var habitID: UUID?
    var navigationToken = 0
    var showSettings = false
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            AppRoute.shared.handleNotification(info)
            completionHandler()
        }
    }
}
