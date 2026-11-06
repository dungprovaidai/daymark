import Foundation
import WidgetKit

@MainActor
extension DaymarkStore {
    /// Writes the small read-only snapshot used by WidgetKit and asks the
    /// system to reload widget timelines. Widgets never open SwiftData.
    func syncWidgetSnapshot() {
        WidgetSnapshotStore.write(WidgetSnapshotBuilder.make(from: self))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Applies checklist changes queued by interactive widgets. Actions are
    /// idempotent because they store the desired value, not a toggle.
    func applyPendingWidgetActions() {
        let actions = WidgetActionStore.pending()
        guard !actions.isEmpty else { return }

        var applied: Set<UUID> = []
        for action in actions {
            guard action.kind == .setChecklist else {
                applied.insert(action.id)
                continue
            }
            guard let field = fields.first(where: { $0.id == action.fieldID && $0.journalID == action.journalID }),
                  let date = SharedDayKey.date(from: action.dayKey) else {
                applied.insert(action.id)
                continue
            }
            if record(field, on: date, update: { $0.checked = action.value }) {
                applied.insert(action.id)
            }
        }
        WidgetActionStore.remove(ids: applied)
    }
}
