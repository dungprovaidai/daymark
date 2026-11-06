import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor enum DataExport {
    static func json(store: DaymarkStore) throws -> Data {
        func date(_ value: Date) -> String { value.ISO8601Format() }
        func optional(_ value: UUID?) -> Any { value.map { $0.uuidString as Any } ?? NSNull() }
        let object: [String: Any] = [
            "format": "Daymark", "schemaVersion": 1, "exportedAt": date(.now),
            "preferences": ["displayName": UserDefaults.standard.string(forKey: "displayName") ?? "", "appearance": UserDefaults.standard.string(forKey: "appearance") ?? "system", "haptics": UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true],
            "journals": store.journals.map { ["id": $0.id.uuidString, "title": $0.title, "icon": $0.icon, "color": $0.color, "position": $0.position, "createdAt": date($0.createdAt)] as [String: Any] },
            "sections": store.sections.map { ["id": $0.id.uuidString, "journalID": $0.journalID.uuidString, "title": $0.title, "position": $0.position] as [String: Any] },
            "fields": store.fields.map { field -> [String: Any] in
                ["id": field.id.uuidString, "journalID": field.journalID.uuidString, "sectionID": optional(field.sectionID),
                 "title": field.title, "kind": field.kindRaw, "icon": field.icon, "color": field.color, "position": field.position,
                 "unit": field.unit, "step": field.step, "target": field.target, "ratingMaximum": field.ratingMaximum,
                 "options": field.options, "archived": field.archived]
            },
            "entries": store.entries.map { ["id": $0.id.uuidString, "key": $0.key, "journalID": $0.journalID.uuidString, "dayKey": $0.dayKey, "date": date($0.date), "note": $0.note, "updatedAt": date($0.updatedAt)] as [String: Any] },
            "values": store.values.map { ["id": $0.id.uuidString, "key": $0.key, "entryID": $0.entryID.uuidString, "fieldID": $0.fieldID.uuidString, "number": $0.number, "text": $0.text, "checked": $0.checked, "updatedAt": date($0.updatedAt)] as [String: Any] },
            "events": store.events.map { event -> [String: Any] in
                ["id": event.id.uuidString, "title": event.title, "description": event.details, "notes": event.notes,
                 "start": date(event.start), "endExclusive": date(event.end), "allDay": event.allDay,
                 "timeZoneID": event.timeZoneID, "location": event.location, "category": event.categoryRaw,
                 "color": event.color, "icon": event.icon, "completed": event.completed,
                 "journalEntryID": optional(event.journalEntryID), "parentSeriesID": optional(event.parentSeriesID), "createdAt": date(event.createdAt)]
            },
            "reminders": store.reminders.map { ["id": $0.id.uuidString, "eventID": $0.eventID.uuidString, "amount": $0.amount, "unit": $0.unitRaw] as [String: Any] },
            "recurrences": store.recurrences.map { ["id": $0.id.uuidString, "eventID": $0.eventID.uuidString, "frequency": $0.frequencyRaw, "interval": $0.interval, "weekdays": $0.weekdays, "until": $0.until.map { date($0) as Any } ?? NSNull()] as [String: Any] },
            "exceptions": store.exceptions.map { ["id": $0.id.uuidString, "key": $0.key, "eventID": $0.eventID.uuidString, "originalStart": date($0.originalStart), "cancelled": $0.cancelled, "completed": $0.completed, "replacementID": optional($0.replacementID)] as [String: Any] },
            "templates": store.templates.map { ["id": $0.id.uuidString, "title": $0.title, "definition": (try? JSONSerialization.jsonObject(with: $0.payload)) ?? NSNull()] as [String: Any] }
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func csv(store: DaymarkStore) -> Data {
        func escape(_ string: String) -> String {
            // Protect spreadsheet consumers from formulas while preserving raw values in JSON.
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { string.hasPrefix($0) }) ? "'" + string : string
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [["date", "journal", "section", "field", "type", "value", "unit", "reflection"]]
        let journals = Dictionary(uniqueKeysWithValues: store.journals.map { ($0.id, $0.title) })
        let fields = Dictionary(uniqueKeysWithValues: store.fields.map { ($0.id, $0) })
        let sections = Dictionary(uniqueKeysWithValues: store.sections.map { ($0.id, $0.title) })
        for entry in store.entries.reversed() {
            let values = store.values.filter { $0.entryID == entry.id }
            if values.isEmpty { rows.append([entry.dayKey, journals[entry.journalID] ?? "", "", "", "", "", "", entry.note]) }
            for value in values {
                guard let field = fields[value.fieldID] else { continue }
                let recorded: String
                switch field.kind {
                case .counter, .rating: recorded = String(value.number)
                case .checkbox: recorded = value.checked ? "true" : "false"
                case .text, .choice: recorded = value.text
                }
                rows.append([entry.dayKey, journals[entry.journalID] ?? "", field.sectionID.flatMap { sections[$0] } ?? "General", field.title, field.kindRaw, recorded, field.unit, entry.note])
            }
        }
        return Data(("\u{FEFF}" + rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")).utf8)
    }
}
