import Foundation
import Observation
import SwiftData

struct EventOccurrence: Identifiable {
    let event: CalendarEvent
    let start: Date
    let end: Date
    let isRecurring: Bool
    let completed: Bool
    var id: String { OccurrenceIdentity.key(eventID: event.id, start: start) }
}

@MainActor @Observable final class DaymarkStore {
    let context: ModelContext
    var journals: [Journal] = []
    var sections: [JournalSection] = []
    var fields: [CustomField] = []
    var entries: [JournalEntry] = []
    var values: [FieldValue] = []
    var events: [CalendarEvent] = []
    var reminders: [Reminder] = []
    var recurrences: [Recurrence] = []
    var exceptions: [EventException] = []
    var templates: [SavedTemplate] = []
    var errorMessage: String?
    var revision = 0
    let notifications = NotificationCoordinator()
    private let notificationSchedulingEnabled: Bool

    init(context: ModelContext, scheduleNotifications: Bool = true) {
        notificationSchedulingEnabled = scheduleNotifications
        self.context = context; context.autosaveEnabled = false
        reload()
        if journals.isEmpty && errorMessage == nil {
            perform { context.insert(Journal(title: "My journal")) }
        }
    }

    func reload() {
        do {
            journals = try context.fetch(FetchDescriptor<Journal>()).sorted { $0.position < $1.position }
            sections = try context.fetch(FetchDescriptor<JournalSection>()).sorted { $0.position < $1.position }
            fields = try context.fetch(FetchDescriptor<CustomField>()).sorted { $0.position < $1.position }
            entries = try context.fetch(FetchDescriptor<JournalEntry>()).sorted { $0.date > $1.date }
            values = try context.fetch(FetchDescriptor<FieldValue>())
            events = try context.fetch(FetchDescriptor<CalendarEvent>())
            reminders = try context.fetch(FetchDescriptor<Reminder>())
            recurrences = try context.fetch(FetchDescriptor<Recurrence>())
            exceptions = try context.fetch(FetchDescriptor<EventException>())
            templates = try context.fetch(FetchDescriptor<SavedTemplate>()).sorted { $0.title < $1.title }
            revision += 1
        } catch { errorMessage = "Your data could not be loaded. \(error.localizedDescription)" }
    }

    @discardableResult func perform(_ operation: () throws -> Void) -> Bool {
        do {
            try operation(); try context.save(); reload(); return true
        } catch {
            context.rollback(); reload()
            errorMessage = "Changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    func activeFields(in journalID: UUID) -> [CustomField] {
        fields.filter { $0.journalID == journalID && !$0.archived }
    }
    func entry(journalID: UUID, date: Date) -> JournalEntry? {
        let day = DayKey.string(date)
        return entries.first { $0.journalID == journalID && $0.dayKey == day }
    }
    func value(fieldID: UUID, entryID: UUID?) -> FieldValue? {
        guard let entryID else { return nil }
        return values.first { $0.entryID == entryID && $0.fieldID == fieldID }
    }
    @discardableResult func record(_ field: CustomField, on date: Date, update: (FieldValue) -> Void) -> Bool {
        perform {
            let entry = self.entry(journalID: field.journalID, date: date) ?? JournalEntry(journalID: field.journalID, date: date)
            if !entries.contains(where: { $0.id == entry.id }) { context.insert(entry) }
            let value = self.value(fieldID: field.id, entryID: entry.id) ?? FieldValue(entryID: entry.id, fieldID: field.id)
            if !values.contains(where: { $0.id == value.id }) { context.insert(value) }
            update(value); value.updatedAt = .now; entry.updatedAt = .now
        }
    }
    @discardableResult func saveNote(journalID: UUID, date: Date, note: String) -> Bool {
        perform {
            let entry = self.entry(journalID: journalID, date: date) ?? JournalEntry(journalID: journalID, date: date)
            if !entries.contains(where: { $0.id == entry.id }) { context.insert(entry) }
            entry.note = note; entry.updatedAt = .now
        }
    }
    func deleteEntry(_ entry: JournalEntry) {
        perform {
            values.filter { $0.entryID == entry.id }.forEach { context.delete($0) }
            events.filter { $0.journalEntryID == entry.id }.forEach { $0.journalEntryID = nil }
            context.delete(entry)
        }
    }
    func deleteJournal(_ journal: Journal) {
        perform {
            let entryIDs = Set(entries.filter { $0.journalID == journal.id }.map(\.id))
            values.filter { entryIDs.contains($0.entryID) }.forEach { context.delete($0) }
            entries.filter { entryIDs.contains($0.id) }.forEach { context.delete($0) }
            events.filter { $0.journalEntryID.map(entryIDs.contains) ?? false }.forEach { $0.journalEntryID = nil }
            fields.filter { $0.journalID == journal.id }.forEach { context.delete($0) }
            sections.filter { $0.journalID == journal.id }.forEach { context.delete($0) }
            context.delete(journal)
        }
    }
    func deleteSection(_ section: JournalSection) {
        perform {
            fields.filter { $0.sectionID == section.id }.forEach { $0.sectionID = nil }
            context.delete(section)
        }
    }
    func progress(journalID: UUID, date: Date) -> (done: Int, total: Int) {
        let fields = activeFields(in: journalID)
        let entry = self.entry(journalID: journalID, date: date)
        let done = fields.filter { field in
            guard let value = value(fieldID: field.id, entryID: entry?.id) else { return false }
            switch field.kind {
            case .checkbox: return value.checked
            case .counter: return field.target > 0 ? value.number >= field.target : true
            case .rating: return value.number > 0
            case .text, .choice: return !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
        return (done, fields.count)
    }

    func schedule(for event: CalendarEvent) -> EventSchedule {
        .init(start: event.start, end: event.end, allDay: event.allDay, timeZoneID: event.timeZoneID,
              rule: recurrences.first { $0.eventID == event.id }?.rule)
    }
    func occurrences(in range: DateInterval) -> [EventOccurrence] {
        let exceptionsByKey = Dictionary(uniqueKeysWithValues: exceptions.map { ($0.key, $0) })
        return events.flatMap { event in
            let schedule = self.schedule(for: event)
            return RecurrenceEngine.occurrences(schedule, in: range).compactMap { time -> EventOccurrence? in
                let key = OccurrenceIdentity.key(eventID: event.id, start: time.start)
                let exception = exceptionsByKey[key]
                guard exception?.cancelled != true && exception?.replacementID == nil else { return nil }
                return .init(event: event, start: time.start, end: time.end, isRecurring: schedule.rule != nil,
                             completed: exception?.completed ?? event.completed)
            }
        }.sorted { $0.start == $1.start ? $0.event.title < $1.event.title : $0.start < $1.start }
    }
    private func exception(for occurrence: EventOccurrence) -> EventException {
        if let existing = exceptions.first(where: { $0.key == occurrence.id }) { return existing }
        let value = EventException(eventID: occurrence.event.id, originalStart: occurrence.start)
        context.insert(value); return value
    }
    func toggleCompletion(_ occurrence: EventOccurrence) {
        if perform({
            if occurrence.isRecurring { exception(for: occurrence).completed = !occurrence.completed }
            else { occurrence.event.completed.toggle() }
        }) { Feedback.success(); reschedule() }
    }
    func deleteEvent(_ occurrence: EventOccurrence, entireSeries: Bool) {
        if perform({
            if occurrence.isRecurring && !entireSeries {
                exception(for: occurrence).cancelled = true
            } else {
                let ids = Set([occurrence.event.id] + events.filter { $0.parentSeriesID == occurrence.event.id }.map(\.id))
                reminders.filter { ids.contains($0.eventID) }.forEach { context.delete($0) }
                recurrences.filter { ids.contains($0.eventID) }.forEach { context.delete($0) }
                exceptions.filter { ids.contains($0.eventID) }.forEach { context.delete($0) }
                // Deleting an already detached occurrence must keep its original slot excluded.
                exceptions.filter { $0.replacementID == occurrence.event.id }.forEach { $0.cancelled = true; $0.replacementID = nil }
                events.filter { ids.contains($0.id) }.forEach { context.delete($0) }
            }
        }) { reschedule() }
    }

    @discardableResult func saveEvent(_ draft: EventDraft, original: EventOccurrence?, entireSeries: Bool) -> Bool {
        let saved = perform {
            let isException = original?.isRecurring == true && !entireSeries
            let resetsSchedule = original.map { entireSeries && $0.isRecurring && draft.scheduleChanged(from: $0.event, rule: schedule(for: $0.event).rule) } ?? false
            let event: CalendarEvent
            if let original, !isException { event = original.event }
            else {
                event = CalendarEvent(title: draft.title, start: draft.start, end: draft.exclusiveEnd)
                context.insert(event)
            }
            if let original, isException {
                event.parentSeriesID = original.event.id
                exception(for: original).replacementID = event.id
            }
            event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            event.details = draft.details; event.notes = draft.notes; event.start = draft.start
            event.end = draft.exclusiveEnd; event.allDay = draft.allDay; event.timeZoneID = draft.timeZoneID
            event.location = draft.location; event.categoryRaw = draft.category.rawValue
            event.color = draft.color; event.icon = draft.icon; event.completed = draft.completed
            event.journalEntryID = draft.journalEntryID
            // A series-wide schedule edit resets old per-date exceptions and detached replacements.
            // The editor explicitly discloses this before the series save.
            if resetsSchedule {
                let detached = events.filter { $0.parentSeriesID == event.id }
                let detachedIDs = Set(detached.map(\.id))
                reminders.filter { detachedIDs.contains($0.eventID) }.forEach { context.delete($0) }
                exceptions.filter { $0.eventID == event.id }.forEach { context.delete($0) }
                detached.forEach { context.delete($0) }
            }
            let existingReminders = reminders.filter { $0.eventID == event.id }
            let keepIDs = Set(draft.reminders.map(\.id))
            existingReminders.filter { !keepIDs.contains($0.id) }.forEach { context.delete($0) }
            for spec in draft.reminders {
                if let existing = existingReminders.first(where: { $0.id == spec.id }) {
                    existing.amount = spec.amount; existing.unitRaw = spec.unit.rawValue
                } else {
                    var copy = spec
                    if isException { copy.id = UUID() }
                    context.insert(Reminder(eventID: event.id, spec: copy))
                }
            }
            let rule = draft.repeats && !isException ? draft.rule : nil
            if let old = recurrences.first(where: { $0.eventID == event.id }) {
                if let rule {
                    old.frequencyRaw = rule.frequency.rawValue; old.interval = rule.interval
                    old.weekdays = rule.weekdays; old.until = rule.until
                } else { context.delete(old) }
            } else if let rule { context.insert(Recurrence(eventID: event.id, rule: rule)) }
        }
        if saved { Feedback.success(); reschedule() }
        return saved
    }
    func reschedule() {
        guard notificationSchedulingEnabled else { return }
        notifications.reconcile(events: events, reminders: reminders, recurrences: recurrences, exceptions: exceptions)
    }
}
