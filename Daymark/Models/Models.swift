import Foundation
import SwiftData

enum FieldKind: String, Codable, CaseIterable, Identifiable {
    case counter, checkbox, text, rating, choice
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .counter: return "number"
        case .checkbox: return "checkmark.circle"
        case .text: return "text.alignleft"
        case .rating: return "star"
        case .choice: return "list.bullet.circle"
        }
    }
}

@Model final class Journal {
    @Attribute(.unique) var id: UUID
    var title: String
    var icon: String
    var color: String
    var position: Int
    var createdAt: Date
    init(title: String, icon: String = "book.closed", color: String = "lavender", position: Int = 0) {
        id = UUID(); self.title = title; self.icon = icon; self.color = color
        self.position = position; createdAt = .now
    }
}

@Model final class JournalSection {
    @Attribute(.unique) var id: UUID
    var journalID: UUID
    var title: String
    var position: Int
    init(journalID: UUID, title: String, position: Int = 0) {
        id = UUID(); self.journalID = journalID; self.title = title; self.position = position
    }
}

@Model final class CustomField {
    @Attribute(.unique) var id: UUID
    var journalID: UUID
    var sectionID: UUID?
    var title: String
    var kindRaw: String
    var icon: String
    var color: String
    var position: Int
    var unit: String
    var step: Double
    var target: Double
    var ratingMaximum: Int
    var options: [String]
    var archived: Bool
    var kind: FieldKind { FieldKind(rawValue: kindRaw) ?? .text }
    init(journalID: UUID, sectionID: UUID? = nil, title: String, kind: FieldKind,
         position: Int = 0, unit: String = "", target: Double = 0) {
        id = UUID(); self.journalID = journalID; self.sectionID = sectionID
        self.title = title; kindRaw = kind.rawValue; icon = kind.icon; color = "lavender"
        self.position = position; self.unit = unit; step = 1; self.target = target
        ratingMaximum = 5; options = []; archived = false
    }
}

@Model final class JournalEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var journalID: UUID
    var dayKey: String
    var date: Date
    var note: String
    var updatedAt: Date
    init(journalID: UUID, date: Date) {
        id = UUID(); self.journalID = journalID; self.date = Calendar.current.startOfDay(for: date)
        dayKey = DayKey.string(date); key = "\(journalID.uuidString)/\(DayKey.string(date))"
        note = ""; updatedAt = .now
    }
}

@Model final class FieldValue {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var entryID: UUID
    var fieldID: UUID
    var number: Double
    var text: String
    var checked: Bool
    var updatedAt: Date
    init(entryID: UUID, fieldID: UUID) {
        id = UUID(); self.entryID = entryID; self.fieldID = fieldID
        key = "\(entryID.uuidString)/\(fieldID.uuidString)"
        number = 0; text = ""; checked = false; updatedAt = .now
    }
}

enum EventCategory: String, CaseIterable, Codable, Identifiable {
    case personal, work, study, health, celebration
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .personal: return "sparkles"
        case .work: return "briefcase"
        case .study: return "graduationcap"
        case .health: return "heart"
        case .celebration: return "gift"
        }
    }
    var color: String {
        switch self {
        case .personal: return "lavender"
        case .work: return "blue"
        case .study: return "amber"
        case .health: return "mint"
        case .celebration: return "rose"
        }
    }
}

@Model final class CalendarEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var notes: String
    var start: Date
    /// Exclusive end, including all-day events.
    var end: Date
    var allDay: Bool
    var timeZoneID: String
    var location: String
    var categoryRaw: String
    var color: String
    var icon: String
    var completed: Bool
    var journalEntryID: UUID?
    var parentSeriesID: UUID?
    var createdAt: Date
    var category: EventCategory { EventCategory(rawValue: categoryRaw) ?? .personal }
    init(title: String, start: Date, end: Date) {
        id = UUID(); self.title = title; self.start = start; self.end = end
        details = ""; notes = ""; allDay = false; timeZoneID = TimeZone.current.identifier
        location = ""; categoryRaw = "personal"; color = "lavender"; icon = "sparkles"
        completed = false; journalEntryID = nil; parentSeriesID = nil; createdAt = .now
    }
}

enum ReminderUnit: String, Codable, CaseIterable, Identifiable {
    case minutes, hours, days, weeks
    var id: String { rawValue }
    var component: Calendar.Component {
        switch self { case .minutes: return .minute; case .hours: return .hour; case .days: return .day; case .weeks: return .weekOfYear }
    }
}

struct ReminderSpec: Codable, Equatable, Identifiable {
    var id = UUID()
    var amount: Int
    var unit: ReminderUnit
    var label: String { amount == 0 ? "At event time" : "\(amount) \(amount == 1 ? String(unit.rawValue.dropLast()) : unit.rawValue) before" }
    var equivalenceKey: String {
        if amount == 0 { return "minutes/0" }
        switch unit {
        case .minutes: return "minutes/\(amount)"
        case .hours: return "minutes/\(amount * 60)"
        case .days: return "days/\(amount)"
        case .weeks: return "days/\(amount * 7)"
        }
    }
    func fireDate(before start: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: unit.component, value: -amount, to: start)
    }
    static let presets: [ReminderSpec] = [
        .init(amount: 0, unit: .minutes), .init(amount: 5, unit: .minutes),
        .init(amount: 15, unit: .minutes), .init(amount: 30, unit: .minutes),
        .init(amount: 1, unit: .hours), .init(amount: 2, unit: .hours),
        .init(amount: 6, unit: .hours), .init(amount: 1, unit: .days), .init(amount: 1, unit: .weeks)
    ]
}

@Model final class Reminder {
    @Attribute(.unique) var id: UUID
    var eventID: UUID
    var amount: Int
    var unitRaw: String
    var spec: ReminderSpec { .init(id: id, amount: amount, unit: ReminderUnit(rawValue: unitRaw) ?? .minutes) }
    init(eventID: UUID, spec: ReminderSpec) {
        id = spec.id; self.eventID = eventID; amount = spec.amount; unitRaw = spec.unit.rawValue
    }
}

@Model final class Recurrence {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var eventID: UUID
    var frequencyRaw: String
    var interval: Int
    var weekdays: [Int]
    var until: Date?
    var rule: RecurrenceRule {
        .init(frequency: RecurrenceFrequency(rawValue: frequencyRaw) ?? .weekly,
              interval: interval, weekdays: weekdays, until: until)
    }
    init(eventID: UUID, rule: RecurrenceRule) {
        id = UUID(); self.eventID = eventID; frequencyRaw = rule.frequency.rawValue
        interval = rule.interval; weekdays = rule.weekdays; until = rule.until
    }
}

@Model final class EventException {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var eventID: UUID
    var originalStart: Date
    var cancelled: Bool
    var completed: Bool
    var replacementID: UUID?
    init(eventID: UUID, originalStart: Date) {
        id = UUID(); self.eventID = eventID; self.originalStart = originalStart
        key = OccurrenceIdentity.key(eventID: eventID, start: originalStart)
        cancelled = false; completed = false; replacementID = nil
    }
}

enum DayKey {
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
