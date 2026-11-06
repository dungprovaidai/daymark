import Foundation
import SwiftUI

struct DaymarkBackup: Decodable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date?
    let preferences: BackupPreferences?
    let journals: [BackupJournal]?
    let sections: [BackupSection]?
    let fields: [BackupField]?
    let entries: [BackupEntry]?
    let values: [BackupValue]?
    let events: [BackupEvent]?
    let reminders: [BackupReminder]?
    let recurrences: [BackupRecurrence]?
    let exceptions: [BackupException]?
    let templates: [BackupTemplate]?
    let habits: [BackupHabit]?
    let habitCompletions: [BackupHabitCompletion]?

    var journalList: [BackupJournal] { journals ?? [] }
    var sectionList: [BackupSection] { sections ?? [] }
    var fieldList: [BackupField] { fields ?? [] }
    var entryList: [BackupEntry] { entries ?? [] }
    var valueList: [BackupValue] { values ?? [] }
    var eventList: [BackupEvent] { events ?? [] }
    var reminderList: [BackupReminder] { reminders ?? [] }
    var recurrenceList: [BackupRecurrence] { recurrences ?? [] }
    var exceptionList: [BackupException] { exceptions ?? [] }
    var templateList: [BackupTemplate] { templates ?? [] }
    var habitList: [BackupHabit] { habits ?? [] }
    var habitCompletionList: [BackupHabitCompletion] { habitCompletions ?? [] }

    var summary: BackupSummary {
        BackupSummary(journals: journalList.count, entries: entryList.count, events: eventList.count,
                      habits: habitList.count, templates: templateList.count)
    }
}

struct BackupSummary {
    let journals: Int
    let entries: Int
    let events: Int
    let habits: Int
    let templates: Int
    var line: String {
        "\(journals) journal\(journals == 1 ? "" : "s"), \(entries) entr\(entries == 1 ? "y" : "ies"), \(events) event\(events == 1 ? "" : "s"), \(habits) habit\(habits == 1 ? "" : "s"), \(templates) template\(templates == 1 ? "" : "s")."
    }
}

struct BackupPreferences: Decodable {
    let displayName: String?
    let appearance: String?
    let haptics: Bool?
}

struct BackupJournal: Decodable {
    let id: UUID; let title: String; let icon: String; let color: String; let position: Int; let createdAt: Date
}
struct BackupSection: Decodable {
    let id: UUID; let journalID: UUID; let title: String; let position: Int
}
struct BackupField: Decodable {
    let id: UUID; let journalID: UUID; let sectionID: UUID?; let title: String; let kind: String
    let icon: String; let color: String; let position: Int; let unit: String; let step: Double
    let target: Double; let ratingMaximum: Int; let options: [String]; let archived: Bool
}
struct BackupEntry: Decodable {
    let id: UUID; let key: String; let journalID: UUID; let dayKey: String; let date: Date
    let note: String; let updatedAt: Date
}
struct BackupValue: Decodable {
    let id: UUID; let key: String; let entryID: UUID; let fieldID: UUID
    let number: Double; let text: String; let checked: Bool; let updatedAt: Date
}
struct BackupEvent: Decodable {
    let id: UUID; let title: String; let details: String; let notes: String
    let start: Date; let endExclusive: Date; let allDay: Bool; let timeZoneID: String
    let location: String; let category: String; let color: String; let icon: String
    let completed: Bool; let journalEntryID: UUID?; let parentSeriesID: UUID?; let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, description, notes, start, endExclusive, allDay, timeZoneID, location
        case category, color, icon, completed, journalEntryID, parentSeriesID, createdAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        details = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        endExclusive = try c.decode(Date.self, forKey: .endExclusive)
        allDay = try c.decode(Bool.self, forKey: .allDay)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "personal"
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "lavender"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
        completed = try c.decode(Bool.self, forKey: .completed)
        journalEntryID = try c.decodeIfPresent(UUID.self, forKey: .journalEntryID)
        parentSeriesID = try c.decodeIfPresent(UUID.self, forKey: .parentSeriesID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}
struct BackupReminder: Decodable {
    let id: UUID; let eventID: UUID; let amount: Int; let unit: String
}
struct BackupRecurrence: Decodable {
    let id: UUID; let eventID: UUID; let frequency: String; let interval: Int; let weekdays: [Int]; let until: Date?
}
struct BackupException: Decodable {
    let id: UUID; let key: String; let eventID: UUID; let originalStart: Date
    let cancelled: Bool; let completed: Bool; let replacementID: UUID?
}
struct BackupTemplate: Decodable {
    let id: UUID; let title: String; let definition: TemplateDefinition?
}
struct BackupHabit: Decodable {
    let id: UUID; let name: String; let details: String; let icon: String; let color: String
    let kind: String; let target: Double; let step: Double; let unit: String
    let frequency: String; let weekdays: [Int]; let periodTarget: Int
    let reminderEnabled: Bool; let reminderHour: Int; let reminderMinute: Int
    let startDate: Date; let endDate: Date?; let archived: Bool; let position: Int
    let createdAt: Date; let updatedAt: Date
}
struct BackupHabitCompletion: Decodable {
    let id: UUID; let key: String; let habitID: UUID; let dayKey: String
    let date: Date; let value: Double; let completed: Bool; let updatedAt: Date
}

enum DataImportError: LocalizedError {
    case tooLarge
    case notDaymark
    case unsupportedVersion(Int)
    case invalid(String)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "This file is too large to be a Daymark backup."
        case .notDaymark: return "This doesn’t look like a Daymark JSON backup."
        case .unsupportedVersion(let version): return "This backup uses schema version \(version), which this version of Daymark can’t restore."
        case .invalid(let detail): return "The backup could not be imported. \(detail)"
        case .saveFailed: return "The backup was not applied. Your existing data was left untouched."
        }
    }
}

@MainActor enum DataImport {
    static func decode(_ data: Data) throws -> DaymarkBackup {
        guard data.count <= 30_000_000 else { throw DataImportError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: DaymarkBackup
        do { backup = try decoder.decode(DaymarkBackup.self, from: data) }
        catch { throw DataImportError.invalid("The JSON structure is incomplete or malformed. \(error.localizedDescription)") }
        guard backup.format == "Daymark" else { throw DataImportError.notDaymark }
        guard (1...2).contains(backup.schemaVersion) else { throw DataImportError.unsupportedVersion(backup.schemaVersion) }
        try validate(backup)
        return backup
    }

    private static func validate(_ backup: DaymarkBackup) throws {
        func unique<T: Hashable>(_ values: [T], _ label: String) throws {
            guard Set(values).count == values.count else { throw DataImportError.invalid("The backup contains duplicate \(label).") }
        }
        try unique(backup.journalList.map(\.id), "journal identifiers")
        try unique(backup.sectionList.map(\.id), "section identifiers")
        try unique(backup.fieldList.map(\.id), "field identifiers")
        try unique(backup.entryList.map(\.id), "entry identifiers")
        try unique(backup.valueList.map(\.id), "value identifiers")
        try unique(backup.eventList.map(\.id), "event identifiers")
        try unique(backup.habitList.map(\.id), "habit identifiers")
        try unique(backup.habitCompletionList.map(\.id), "habit completion identifiers")

        let journalIDs = Set(backup.journalList.map(\.id))
        let sectionIDs = Set(backup.sectionList.map(\.id))
        let fieldIDs = Set(backup.fieldList.map(\.id))
        let entryIDs = Set(backup.entryList.map(\.id))
        let eventIDs = Set(backup.eventList.map(\.id))
        let habitIDs = Set(backup.habitList.map(\.id))

        if !backup.sectionList.allSatisfy({ journalIDs.contains($0.journalID) }) {
            throw DataImportError.invalid("A section refers to a missing journal.")
        }
        if !backup.fieldList.allSatisfy({ journalIDs.contains($0.journalID) && ($0.sectionID == nil || sectionIDs.contains($0.sectionID!)) }) {
            throw DataImportError.invalid("A field refers to a missing journal or section.")
        }
        if !backup.entryList.allSatisfy({ journalIDs.contains($0.journalID) }) {
            throw DataImportError.invalid("An entry refers to a missing journal.")
        }
        try unique(backup.entryList.map { "\($0.journalID)/\($0.dayKey)" }, "journal/day entries")
        if !backup.valueList.allSatisfy({ entryIDs.contains($0.entryID) && fieldIDs.contains($0.fieldID) }) {
            throw DataImportError.invalid("A recorded value refers to a missing entry or field.")
        }
        if !backup.eventList.allSatisfy({
            ($0.journalEntryID == nil || entryIDs.contains($0.journalEntryID!)) &&
            ($0.parentSeriesID == nil || eventIDs.contains($0.parentSeriesID!))
        }) {
            throw DataImportError.invalid("An event refers to a missing journal entry or series.")
        }
        if !backup.reminderList.allSatisfy({ eventIDs.contains($0.eventID) }) ||
           !backup.recurrenceList.allSatisfy({ eventIDs.contains($0.eventID) }) ||
           !backup.exceptionList.allSatisfy({ eventIDs.contains($0.eventID) && ($0.replacementID == nil || eventIDs.contains($0.replacementID!)) }) {
            throw DataImportError.invalid("A reminder or repeat rule refers to a missing event.")
        }
        if !backup.habitCompletionList.allSatisfy({ habitIDs.contains($0.habitID) }) {
            throw DataImportError.invalid("A habit check-in refers to a missing habit.")
        }
        if !backup.habitList.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw DataImportError.invalid("A habit is missing its name.")
        }
    }

    static func apply(_ backup: DaymarkBackup, store: DaymarkStore) throws {
        var journalMap: [UUID: UUID] = [:]
        var sectionMap: [UUID: UUID] = [:]
        var fieldMap: [UUID: UUID] = [:]
        var entryMap: [UUID: UUID] = [:]
        var eventMap: [UUID: UUID] = [:]
        var habitMap: [UUID: UUID] = [:]
        for item in backup.journalList { journalMap[item.id] = UUID() }
        for item in backup.sectionList { sectionMap[item.id] = UUID() }
        for item in backup.fieldList { fieldMap[item.id] = UUID() }
        for item in backup.entryList { entryMap[item.id] = UUID() }
        for item in backup.eventList { eventMap[item.id] = UUID() }
        for item in backup.habitList { habitMap[item.id] = UUID() }

        let saved = store.perform {
            // New identifiers and keys mean the import can be built beside the
            // current data and rolled back as one transaction if anything fails.
            store.habitCompletions.forEach { store.context.delete($0) }
            store.habits.forEach { store.context.delete($0) }
            store.values.forEach { store.context.delete($0) }
            store.entries.forEach { store.context.delete($0) }
            store.fields.forEach { store.context.delete($0) }
            store.sections.forEach { store.context.delete($0) }
            store.journals.forEach { store.context.delete($0) }
            store.reminders.forEach { store.context.delete($0) }
            store.recurrences.forEach { store.context.delete($0) }
            store.exceptions.forEach { store.context.delete($0) }
            store.events.forEach { store.context.delete($0) }
            store.templates.forEach { store.context.delete($0) }

            for item in backup.journalList {
                let journal = Journal(title: item.title, icon: item.icon, color: item.color, position: item.position)
                journal.id = journalMap[item.id]!
                journal.createdAt = item.createdAt
                store.context.insert(journal)
            }
            for item in backup.sectionList {
                guard let journalID = journalMap[item.journalID] else { continue }
                let section = JournalSection(journalID: journalID, title: item.title, position: item.position)
                section.id = sectionMap[item.id]!
                store.context.insert(section)
            }
            for item in backup.fieldList {
                guard let journalID = journalMap[item.journalID] else { continue }
                let field = CustomField(journalID: journalID, sectionID: item.sectionID.flatMap { sectionMap[$0] },
                                        title: item.title, kind: FieldKind(rawValue: item.kind) ?? .text,
                                        position: item.position, unit: item.unit, target: item.target)
                field.id = fieldMap[item.id]!
                field.icon = item.icon; field.color = item.color; field.step = item.step
                field.ratingMaximum = max(1, item.ratingMaximum); field.options = item.options; field.archived = item.archived
                store.context.insert(field)
            }
            for item in backup.entryList {
                guard let journalID = journalMap[item.journalID] else { continue }
                let entry = JournalEntry(journalID: journalID, date: item.date)
                entry.id = entryMap[item.id]!
                entry.dayKey = item.dayKey
                entry.key = "\(journalID.uuidString)/\(item.dayKey)"
                entry.date = Calendar.current.startOfDay(for: item.date)
                entry.note = item.note; entry.updatedAt = item.updatedAt
                store.context.insert(entry)
            }
            for item in backup.valueList {
                guard let entryID = entryMap[item.entryID], let fieldID = fieldMap[item.fieldID] else { continue }
                let value = FieldValue(entryID: entryID, fieldID: fieldID)
                value.id = UUID()
                value.number = item.number; value.text = item.text; value.checked = item.checked
                value.updatedAt = item.updatedAt
                store.context.insert(value)
            }
            for item in backup.eventList {
                let event = CalendarEvent(title: item.title, start: item.start, end: item.endExclusive)
                event.id = eventMap[item.id]!
                event.details = item.details; event.notes = item.notes
                event.allDay = item.allDay; event.timeZoneID = item.timeZoneID
                event.location = item.location; event.categoryRaw = item.category
                event.color = item.color; event.icon = item.icon; event.completed = item.completed
                event.journalEntryID = item.journalEntryID.flatMap { entryMap[$0] }
                event.parentSeriesID = item.parentSeriesID.flatMap { eventMap[$0] }
                event.createdAt = item.createdAt
                store.context.insert(event)
            }
            for item in backup.reminderList {
                guard let eventID = eventMap[item.eventID] else { continue }
                let spec = ReminderSpec(amount: item.amount, unit: ReminderUnit(rawValue: item.unit) ?? .minutes)
                let reminder = Reminder(eventID: eventID, spec: spec)
                reminder.id = UUID()
                store.context.insert(reminder)
            }
            for item in backup.recurrenceList {
                guard let eventID = eventMap[item.eventID] else { continue }
                let rule = RecurrenceRule(frequency: RecurrenceFrequency(rawValue: item.frequency) ?? .weekly,
                                          interval: max(1, item.interval), weekdays: item.weekdays, until: item.until)
                let recurrence = Recurrence(eventID: eventID, rule: rule)
                recurrence.id = UUID()
                store.context.insert(recurrence)
            }
            for item in backup.exceptionList {
                guard let eventID = eventMap[item.eventID] else { continue }
                let exception = EventException(eventID: eventID, originalStart: item.originalStart)
                exception.id = UUID()
                exception.cancelled = item.cancelled; exception.completed = item.completed
                exception.replacementID = item.replacementID.flatMap { eventMap[$0] }
                store.context.insert(exception)
            }
            for item in backup.templateList {
                guard let definition = item.definition, let payload = try? JSONEncoder().encode(definition) else { continue }
                let template = SavedTemplate(title: item.title, payload: payload)
                template.id = UUID()
                store.context.insert(template)
            }
            for item in backup.habitList {
                let habit = Habit(name: item.name, icon: item.icon, color: item.color)
                habit.id = habitMap[item.id]!
                habit.details = item.details
                habit.kindRaw = item.kind
                habit.target = item.target; habit.step = max(0.01, item.step); habit.unit = item.unit
                habit.frequencyRaw = item.frequency; habit.weekdays = item.weekdays
                habit.periodTarget = max(1, item.periodTarget)
                habit.reminderEnabled = item.reminderEnabled
                habit.reminderHour = item.reminderHour; habit.reminderMinute = item.reminderMinute
                habit.startDate = item.startDate; habit.endDate = item.endDate
                habit.archived = item.archived; habit.position = item.position
                habit.createdAt = item.createdAt; habit.updatedAt = item.updatedAt
                store.context.insert(habit)
            }
            for item in backup.habitCompletionList {
                guard let habitID = habitMap[item.habitID] else { continue }
                let completion = HabitCompletion(habitID: habitID, date: item.date)
                completion.id = UUID()
                completion.dayKey = item.dayKey
                completion.key = "\(habitID.uuidString)/\(item.dayKey)"
                completion.date = Calendar.current.startOfDay(for: item.date)
                completion.value = item.value; completion.completed = item.completed; completion.updatedAt = item.updatedAt
                store.context.insert(completion)
            }
        }
        guard saved else { throw DataImportError.saveFailed }

        if let preferences = backup.preferences {
            if let displayName = preferences.displayName { UserDefaults.standard.set(displayName, forKey: "displayName") }
            if let appearance = preferences.appearance { UserDefaults.standard.set(appearance, forKey: "appearance") }
            if let haptics = preferences.haptics { UserDefaults.standard.set(haptics, forKey: "haptics") }
        }
        store.reschedule()
        store.syncWidgetSnapshot()
    }
}
