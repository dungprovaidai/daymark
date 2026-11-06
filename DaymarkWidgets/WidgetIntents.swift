import AppIntents
import Foundation
import WidgetKit

struct WidgetJournalEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Journal")
    static var defaultQuery = WidgetJournalQuery()

    var id: String
    var title: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: nil, image: .init(systemName: icon))
    }

    init(_ journal: WidgetJournalInfo) {
        id = journal.id.uuidString
        title = journal.title
        icon = journal.icon
    }

    init(id: String, title: String, icon: String) {
        self.id = id; self.title = title; self.icon = icon
    }
}

struct WidgetJournalQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetJournalEntity] {
        let snapshot = WidgetSnapshotStore.read()
        return snapshot?.journals.filter { identifiers.contains($0.id.uuidString) }.map(WidgetJournalEntity.init) ?? []
    }

    func suggestedEntities() async throws -> [WidgetJournalEntity] {
        WidgetSnapshotStore.read()?.journals.map(WidgetJournalEntity.init) ?? []
    }
}

struct WidgetSectionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Section")
    static var defaultQuery = WidgetSectionQuery()

    var id: String
    var title: String
    var journalTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(journalTitle)")
    }

    init(section: WidgetSectionInfo, journal: WidgetJournalInfo) {
        id = section.id.uuidString
        title = section.title
        journalTitle = journal.title
    }

    init(id: String, title: String, journalTitle: String) {
        self.id = id; self.title = title; self.journalTitle = journalTitle
    }
}

struct WidgetSectionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetSectionEntity] {
        allSections().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetSectionEntity] {
        allSections()
    }

    private func allSections() -> [WidgetSectionEntity] {
        guard let snapshot = WidgetSnapshotStore.read() else { return [] }
        return snapshot.journals.flatMap { journal in
            journal.sections.map { WidgetSectionEntity(section: $0, journal: journal) }
        }
    }
}

enum WidgetInformation: String, AppEnum {
    case progress, nextEvent, agenda, checklist, reminders

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Information")
    static var caseDisplayRepresentations: [WidgetInformation: DisplayRepresentation] = [
        .progress: DisplayRepresentation(title: "Journal progress"),
        .nextEvent: DisplayRepresentation(title: "Next event"),
        .agenda: DisplayRepresentation(title: "Upcoming events"),
        .checklist: DisplayRepresentation(title: "Checklist"),
        .reminders: DisplayRepresentation(title: "Reminders")
    ]
}

struct DaymarkWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Daymark Widget"
    static var description = IntentDescription("Choose a journal, section, and the information you want to see.")

    @Parameter(title: "Journal")
    var journal: WidgetJournalEntity?

    @Parameter(title: "Section")
    var section: WidgetSectionEntity?

    @Parameter(title: "Focus")
    var information: WidgetInformation?

    init() {
        journal = nil
        section = nil
        information = .progress
    }
}

struct ToggleChecklistIntent: AppIntent {
    static var title: LocalizedStringResource = "Update checklist item"
    static var description = IntentDescription("Marks a Daymark checklist item complete or incomplete.")

    @Parameter(title: "Field ID")
    var fieldID: String

    @Parameter(title: "Journal ID")
    var journalID: String

    @Parameter(title: "Day")
    var dayKey: String

    @Parameter(title: "Currently checked")
    var checked: Bool

    init() { }

    init(fieldID: UUID, journalID: UUID, dayKey: String, checked: Bool) {
        self.fieldID = fieldID.uuidString
        self.journalID = journalID.uuidString
        self.dayKey = dayKey
        self.checked = checked
    }

    func perform() async throws -> some IntentResult {
        guard let field = UUID(uuidString: fieldID), let journal = UUID(uuidString: journalID) else {
            return .result()
        }
        let newValue = !checked
        WidgetSnapshotStore.update { snapshot in
            guard let index = snapshot.checklist.firstIndex(where: { $0.fieldID == field }) else { return }
            let wasChecked = snapshot.checklist[index].checked
            snapshot.checklist[index].checked = newValue
            guard wasChecked != newValue,
                  let progressIndex = snapshot.progress.firstIndex(where: { $0.journalID == journal }) else { return }
            let old = snapshot.progress[progressIndex]
            let next = max(0, min(old.total, old.done + (newValue ? 1 : -1)))
            snapshot.progress[progressIndex] = WidgetJournalProgress(
                journalID: old.journalID,
                done: next,
                total: old.total,
                note: old.note
            )
        }
        WidgetActionStore.enqueue(WidgetAction(
            fieldID: field,
            journalID: journal,
            dayKey: dayKey,
            value: newValue
        ))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
