import Foundation

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var unit: String {
        switch self { case .daily: return "day"; case .weekly: return "week"; case .monthly: return "month"; case .yearly: return "year" }
    }
}

struct RecurrenceRule: Codable, Equatable {
    var frequency: RecurrenceFrequency = .weekly
    var interval: Int = 1
    /// Calendar weekday numbers: Sunday = 1 ... Saturday = 7.
    var weekdays: [Int] = []
    var until: Date?
}

struct EventSchedule {
    var start: Date
    var end: Date
    var allDay: Bool
    var timeZoneID: String
    var rule: RecurrenceRule?
}

struct OccurrenceTime: Equatable {
    let start: Date
    let end: Date
}

enum OccurrenceIdentity {
    static func key(eventID: UUID, start: Date) -> String {
        "\(eventID.uuidString)/\(Int(start.timeIntervalSince1970.rounded()))"
    }
}

/// A bounded date-range expansion. Calendar arithmetic preserves wall-clock time
/// across DST; invalid month days (e.g. February 31) are skipped, never clamped.
enum RecurrenceEngine {
    static func calendar(for schedule: EventSchedule) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: schedule.timeZoneID) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    static func occurrences(_ schedule: EventSchedule, in range: DateInterval) -> [OccurrenceTime] {
        let cal = calendar(for: schedule)
        guard schedule.end > schedule.start else { return [] }
        guard let rule = schedule.rule else {
            return overlaps(start: schedule.start, end: schedule.end, range: range)
                ? [.init(start: schedule.start, end: schedule.end)] : []
        }
        let anchor = cal.startOfDay(for: schedule.start)
        let endDay = cal.startOfDay(for: schedule.end)
        let span = max(0, cal.dateComponents([.day], from: anchor, to: endDay).day ?? 0)
        let earliest = cal.date(byAdding: .day, value: -span - 1, to: range.start) ?? range.start
        var day = max(anchor, cal.startOfDay(for: earliest))
        let last = min(range.end, rule.until.map { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0)) ?? $0 } ?? range.end)
        let time = cal.dateComponents([.hour, .minute, .second], from: schedule.start)
        let endTime = cal.dateComponents([.hour, .minute, .second], from: schedule.end)
        let anchorParts = cal.dateComponents([.year, .month, .day, .weekday], from: anchor)
        let interval = max(1, rule.interval)
        var result: [OccurrenceTime] = []
        while day < last {
            let parts = cal.dateComponents([.year, .month, .day, .weekday], from: day)
            let days = cal.dateComponents([.day], from: anchor, to: day).day ?? 0
            let matches: Bool
            switch rule.frequency {
            case .daily:
                matches = days % interval == 0
            case .weekly:
                let baseWeek = cal.dateInterval(of: .weekOfYear, for: anchor)!.start
                let week = cal.dateInterval(of: .weekOfYear, for: day)!.start
                let weeks = (cal.dateComponents([.day], from: baseWeek, to: week).day ?? 0) / 7
                let selected = rule.weekdays.isEmpty ? [anchorParts.weekday ?? 1] : rule.weekdays
                matches = weeks % interval == 0 && selected.contains(parts.weekday ?? 1)
            case .monthly:
                let months = ((parts.year ?? 0) - (anchorParts.year ?? 0)) * 12 + (parts.month ?? 0) - (anchorParts.month ?? 0)
                matches = months % interval == 0 && parts.day == anchorParts.day
            case .yearly:
                matches = ((parts.year ?? 0) - (anchorParts.year ?? 0)) % interval == 0
                    && parts.month == anchorParts.month && parts.day == anchorParts.day
            }
            if matches,
               let start = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
                                    of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
               let endDate = cal.date(byAdding: .day, value: span, to: day),
               let proposedEnd = cal.date(bySettingHour: endTime.hour ?? 0, minute: endTime.minute ?? 0, second: endTime.second ?? 0,
                                  of: endDate, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
               start >= schedule.start {
                // When DST collapses both wall times into the same instant, preserve
                // the original elapsed duration instead of dropping the event.
                let end = proposedEnd > start ? proposedEnd : start.addingTimeInterval(schedule.end.timeIntervalSince(schedule.start))
                if overlaps(start: start, end: end, range: range) { result.append(.init(start: start, end: end)) }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    private static func overlaps(start: Date, end: Date, range: DateInterval) -> Bool {
        start < range.end && end > range.start
    }
}
