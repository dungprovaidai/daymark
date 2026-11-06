import Foundation
import SwiftData

struct TemplateField: Codable, Identifiable {
    var id = UUID()
    var title: String
    var kind: FieldKind
    var section: String?
    var icon: String
    var color: String = "lavender"
    var unit = ""
    var step: Double = 1
    var target: Double = 0
    var maximum = 5
    var options: [String] = []
}

struct TemplateDefinition: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var icon: String
    var color: String
    var fields: [TemplateField]
    static let builtIns: [TemplateDefinition] = [
        .init(id: "daily", title: "Daily rhythm", subtitle: "A simple check-in with yourself.", icon: "sun.max", color: "lavender", fields: [
            .init(title: "How are you feeling?", kind: .choice, section: "Check in", icon: "sparkles", options: ["Wonderful", "Good", "Okay", "Low", "Difficult"]),
            .init(title: "One good thing", kind: .text, section: "Check in", icon: "pencil"),
            .init(title: "Time outside", kind: .checkbox, section: "Small intentions", icon: "leaf", color: "mint"),
            .init(title: "Today’s energy", kind: .rating, section: "Small intentions", icon: "star", color: "amber")
        ]),
        .init(id: "study", title: "Focused learning", subtitle: "Notice the effort behind your progress.", icon: "graduationcap", color: "blue", fields: [
            .init(title: "Focus sessions", kind: .counter, section: "Practice", icon: "number", color: "blue", unit: "sessions", target: 4),
            .init(title: "What clicked today?", kind: .text, section: "Reflect", icon: "pencil"),
            .init(title: "Reviewed my notes", kind: .checkbox, section: "Reflect", icon: "checkmark.circle", color: "mint")
        ]),
        .init(id: "wellbeing", title: "Everyday wellbeing", subtitle: "Gentle habits, at your own pace.", icon: "heart", color: "rose", fields: [
            .init(title: "Movement", kind: .counter, section: "Care", icon: "figure.walk", color: "mint", unit: "minutes", step: 5, target: 30),
            .init(title: "Rest quality", kind: .rating, section: "Care", icon: "moon", color: "lavender"),
            .init(title: "Something I’m grateful for", kind: .text, section: "Reflect", icon: "heart", color: "rose")
        ])
    ]
}

@Model final class SavedTemplate {
    @Attribute(.unique) var id: UUID
    var title: String
    var payload: Data
    init(title: String, payload: Data) { id = UUID(); self.title = title; self.payload = payload }
    var definition: TemplateDefinition? { try? JSONDecoder().decode(TemplateDefinition.self, from: payload) }
}

extension DaymarkStore {
    func applyTemplate(_ template: TemplateDefinition, to journal: Journal?) -> Bool {
        perform {
            let target = journal ?? Journal(title: template.title, icon: template.icon, color: template.color, position: journals.count)
            if journal == nil { context.insert(target) }
            var sectionIDs: [String: UUID] = [:]
            var position = sections.filter { $0.journalID == target.id }.count
            for field in template.fields {
                if let title = field.section, sectionIDs[title] == nil {
                    let section = JournalSection(journalID: target.id, title: title, position: position)
                    context.insert(section); sectionIDs[title] = section.id; position += 1
                }
            }
            let fieldOffset = fields.filter { $0.journalID == target.id }.count
            for (index, source) in template.fields.enumerated() {
                let field = CustomField(journalID: target.id, sectionID: source.section.flatMap { sectionIDs[$0] }, title: source.title,
                                        kind: source.kind, position: fieldOffset + index, unit: source.unit, target: source.target)
                field.icon = source.icon; field.color = source.color; field.step = source.step
                field.ratingMaximum = source.maximum; field.options = source.options
                context.insert(field)
            }
        }
    }
    func saveTemplate(from journal: Journal) {
        perform {
            let definition = TemplateDefinition(id: UUID().uuidString, title: journal.title, subtitle: "Your own collection of fields.", icon: journal.icon, color: journal.color,
                fields: activeFields(in: journal.id).map { field in
                    TemplateField(title: field.title, kind: field.kind, section: sections.first { $0.id == field.sectionID }?.title,
                                  icon: field.icon, color: field.color, unit: field.unit, step: field.step,
                                  target: field.target, maximum: field.ratingMaximum, options: field.options)
                })
            context.insert(SavedTemplate(title: journal.title, payload: try JSONEncoder().encode(definition)))
        }
    }
}
