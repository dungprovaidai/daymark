import XCTest
import SwiftData
@testable import Daymark

@MainActor final class StoreAndNotificationTests: XCTestCase {
    private func makeStore() throws -> (ModelContainer, DaymarkStore) {
        let schema = Schema([Journal.self, JournalSection.self, CustomField.self, JournalEntry.self, FieldValue.self, CalendarEvent.self, Reminder.self, Recurrence.self, EventException.self, SavedTemplate.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        return (container, DaymarkStore(context: container.mainContext, scheduleNotifications: false))
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testRepeatedCounterWritesReuseEntryAndValueAndReload() throws {
        let (container, store) = try makeStore()
        let journal = store.journals[0]
        let field = CustomField(journalID: journal.id, title: "Focus", kind: .counter)
        store.perform { store.context.insert(field) }
        store.record(field, on: .now) { $0.number = 1 }
        store.record(field, on: .now) { $0.number += 1 }
        let reloaded = DaymarkStore(context: ModelContext(container), scheduleNotifications: false)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.values.count, 1)
        XCTAssertEqual(reloaded.values.first?.number, 2)
    }
    func testDeletingJournalKeepsEventsAndRemovesLink() throws {
        let (_, store) = try makeStore()
        let journal = store.journals[0]
        store.saveNote(journalID: journal.id, date: .now, note: "Keep a moment")
        let event = CalendarEvent(title: "Meeting", start: .now, end: .now.addingTimeInterval(3600))
        event.journalEntryID = store.entries[0].id
        store.perform { store.context.insert(event) }
        store.deleteJournal(journal)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertNil(store.events[0].journalEntryID)
    }
    func testEditingOneOccurrenceDoesNotDuplicateOriginal() throws {
        let (_, store) = try makeStore()
        let start = date("2026-11-06T09:00:00Z")
        var draft = EventDraft(date: start); draft.title = "Practice"; draft.start = start; draft.end = start.addingTimeInterval(3600)
        draft.timeZoneID = "UTC"; draft.repeats = true; draft.rule = .init(frequency: .daily)
        XCTAssertTrue(store.saveEvent(draft, original: nil, entireSeries: false))
        let range = DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(3 * 86400))
        let original = store.occurrences(in: range)[1]
        var edited = EventDraft(occurrence: original, store: store, entireSeries: false)
        edited.title = "Moved practice"; edited.start = original.start.addingTimeInterval(7200); edited.end = original.end.addingTimeInterval(7200)
        XCTAssertTrue(store.saveEvent(edited, original: original, entireSeries: false))
        let occurrences = store.occurrences(in: range)
        XCTAssertFalse(occurrences.contains { $0.id == original.id })
        XCTAssertEqual(occurrences.filter { $0.event.title == "Moved practice" }.count, 1)
        XCTAssertEqual(store.recurrences.count, 1)
    }
    func testDeletingOccurrenceKeepsSeriesThenWholeSeriesRemovesReminders() throws {
        let (_, store) = try makeStore()
        let start = date("2030-11-06T09:00:00Z")
        var draft = EventDraft(date: start); draft.title = "Practice"; draft.start = start; draft.end = start.addingTimeInterval(3600)
        draft.timeZoneID = "UTC"; draft.repeats = true; draft.rule = .init(frequency: .daily)
        draft.reminders = [.init(amount: 15, unit: .minutes)]
        XCTAssertTrue(store.saveEvent(draft, original: nil, entireSeries: false))
        let range = DateInterval(start: start, end: start.addingTimeInterval(3 * 86400))
        let original = store.occurrences(in: range)[0]
        store.deleteEvent(original, entireSeries: false)
        XCTAssertEqual(store.events.count, 1)
        XCTAssertFalse(store.occurrences(in: range).contains { $0.id == original.id })
        store.deleteEvent(store.occurrences(in: range)[0], entireSeries: true)
        XCTAssertTrue(store.events.isEmpty); XCTAssertTrue(store.reminders.isEmpty); XCTAssertTrue(store.recurrences.isEmpty); XCTAssertTrue(store.exceptions.isEmpty)
    }
    func testSeriesScheduleChangeResetsExceptions() throws {
        let (_, store) = try makeStore()
        let start = date("2030-11-06T09:00:00Z")
        var draft = EventDraft(date: start); draft.title = "Series"; draft.start = start; draft.end = start.addingTimeInterval(3600)
        draft.repeats = true; draft.rule = .init(frequency: .daily); draft.timeZoneID = "UTC"
        store.saveEvent(draft, original: nil, entireSeries: false)
        let range = DateInterval(start: start, end: start.addingTimeInterval(3 * 86400))
        let occurrence = store.occurrences(in: range)[0]
        store.toggleCompletion(occurrence)
        XCTAssertEqual(store.exceptions.count, 1)
        var edit = EventDraft(occurrence: occurrence, store: store, entireSeries: true)
        edit.start = start.addingTimeInterval(3600); edit.end = start.addingTimeInterval(7200)
        store.saveEvent(edit, original: occurrence, entireSeries: true)
        XCTAssertTrue(store.exceptions.isEmpty)
    }
    func testNotificationIDsAreStableAndCancellationAndCompletionAreExcluded() throws {
        let now = date("2030-11-06T08:00:00Z")
        let event = CalendarEvent(title: "Meeting", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800))
        let reminder = Reminder(eventID: event.id, spec: .init(amount: 15, unit: .minutes))
        let plan = NotificationCoordinator.makePlan(events: [event], reminders: [reminder], recurrences: [], exceptions: [], now: now)
        let again = NotificationCoordinator.makePlan(events: [event], reminders: [reminder], recurrences: [], exceptions: [], now: now)
        XCTAssertEqual(plan.map(\.id), again.map(\.id)); XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate, event.start.addingTimeInterval(-900))
        let exception = EventException(eventID: event.id, originalStart: event.start); exception.cancelled = true
        XCTAssertTrue(NotificationCoordinator.makePlan(events: [event], reminders: [reminder], recurrences: [], exceptions: [exception], now: now).isEmpty)
        event.completed = true
        XCTAssertTrue(NotificationCoordinator.makePlan(events: [event], reminders: [reminder], recurrences: [], exceptions: [], now: now).isEmpty)
    }
    func testPastRemindersAreNotScheduled() {
        let now = date("2030-11-06T08:00:00Z")
        let event = CalendarEvent(title: "Soon", start: now.addingTimeInterval(300), end: now.addingTimeInterval(3600))
        let reminders = [Reminder(eventID: event.id, spec: .init(amount: 15, unit: .minutes)), Reminder(eventID: event.id, spec: .init(amount: 0, unit: .minutes))]
        let plan = NotificationCoordinator.makePlan(events: [event], reminders: reminders, recurrences: [], exceptions: [], now: now)
        XCTAssertEqual(plan.count, 1); XCTAssertEqual(plan[0].fireDate, event.start)
    }
    func testJSONExportIncludesLinkedModelsAndCSVQuotesAndNeutralizesFormulas() throws {
        let (_, store) = try makeStore(); let journal = store.journals[0]
        let field = CustomField(journalID: journal.id, title: "A, B", kind: .text)
        store.perform { store.context.insert(field) }; store.record(field, on: .now) { $0.text = "=SUM(1,2)" }
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: DataExport.json(store: store)) as? [String: Any])
        XCTAssertEqual((json["fields"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((json["values"] as? [[String: Any]])?.first?["text"] as? String, "=SUM(1,2)")
        let csv = String(decoding: DataExport.csv(store: store), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"A, B\"")); XCTAssertTrue(csv.contains("\"'=SUM(1,2)\""))
    }
}
