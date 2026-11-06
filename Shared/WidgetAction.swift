import Foundation

struct WidgetAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case setChecklist
    }

    var id = UUID()
    var kind = Kind.setChecklist
    var fieldID: UUID
    var journalID: UUID
    var dayKey: String
    var value: Bool
    var createdAt = Date()
}

/// Writes are queued so the widget extension never opens SwiftData and never
/// risks a concurrent write with the app. The app applies pending actions on
/// its next activation and removes them afterwards.
enum WidgetActionStore {
    static func enqueue(_ action: WidgetAction) {
        WidgetFileLock.withLock {
            var actions = readUnlocked()
            if !actions.contains(where: { $0.id == action.id }) {
                actions.append(action)
                writeUnlocked(actions)
            }
        }
    }

    static func pending() -> [WidgetAction] {
        WidgetFileLock.withLock { readUnlocked() }
    }

    static func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        WidgetFileLock.withLock {
            let remaining = readUnlocked().filter { !ids.contains($0.id) }
            writeUnlocked(remaining)
        }
    }

    private static func readUnlocked() -> [WidgetAction] {
        guard let data = try? Data(contentsOf: DaymarkShared.actionsURL) else { return [] }
        return (try? JSONDecoder().decode([WidgetAction].self, from: data)) ?? []
    }

    private static func writeUnlocked(_ actions: [WidgetAction]) {
        DaymarkShared.ensureDirectory()
        if actions.isEmpty {
            try? FileManager.default.removeItem(at: DaymarkShared.actionsURL)
            return
        }
        guard let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: DaymarkShared.actionsURL, options: .atomic)
    }
}
