import Foundation

struct EventDraft {
    var title = ""
    var details = ""
    var notes = ""
    var start: Date
    /// Inclusive last day in all-day mode; an exact time otherwise.
    var end: Date
    var allDay = false
    var timeZoneID = TimeZone.current.identifier
    var location = ""
    var category = EventCategory.personal
    var color = "lavender"
    var icon = "sparkles"
    var completed = false
    var journalEntryID: UUID?
    var reminders: [ReminderSpec] = []
    var repeats = false
    var rule = RecurrenceRule()
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return cal
    }
    var exclusiveEnd: Date {
        allDay ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))! : end
    }
    var validation: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give your event a title." }
        if exclusiveEnd <= start { return "End must be after start." }
        if repeats, let until = rule.until, calendar.startOfDay(for: until) < calendar.startOfDay(for: start) {
            return "The repeat end date must be on or after the start date."
        }
        return nil
    }
    init(date: Date = .now) {
        let cal = Calendar.current
        if cal.isDateInToday(date), let nextHour = cal.date(byAdding: .hour, value: 1, to: .now) {
            start = cal.date(bySettingHour: cal.component(.hour, from: nextHour), minute: 0, second: 0, of: nextHour) ?? nextHour
        } else {
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        end = start.addingTimeInterval(3600)
    }
    @MainActor init(occurrence: EventOccurrence, store: DaymarkStore, entireSeries: Bool) {
        let event = occurrence.event
        title = event.title; details = event.details; notes = event.notes
        start = entireSeries ? event.start : occurrence.start
        end = entireSeries ? event.end : occurrence.end
        allDay = event.allDay; timeZoneID = event.timeZoneID
        location = event.location; category = event.category; color = event.color; icon = event.icon
        completed = entireSeries ? event.completed : occurrence.completed; journalEntryID = event.journalEntryID
        reminders = store.reminders.filter { $0.eventID == event.id }.map(\.spec)
        if entireSeries, let recurrence = store.recurrences.first(where: { $0.eventID == event.id }) {
            repeats = true; rule = recurrence.rule
        }
        if allDay { end = calendar.date(byAdding: .day, value: -1, to: end) ?? end }
    }
    func scheduleChanged(from event: CalendarEvent, rule oldRule: RecurrenceRule?) -> Bool {
        start != event.start || exclusiveEnd != event.end || allDay != event.allDay || timeZoneID != event.timeZoneID
            || (repeats ? rule : nil) != oldRule
    }
    mutating func setAllDay(_ value: Bool) {
        if value {
            start = calendar.startOfDay(for: start)
            end = max(start, calendar.startOfDay(for: end))
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: start) ?? start
            end = max(start.addingTimeInterval(3600), calendar.date(bySettingHour: 10, minute: 0, second: 0, of: end) ?? end)
        }
    }
}
