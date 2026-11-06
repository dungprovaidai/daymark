import Foundation

@MainActor
enum WidgetSnapshotBuilder {
    static func make(from store: DaymarkStore, now: Date = .now) -> WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let rangeEnd = calendar.date(byAdding: .day, value: 31, to: now) ?? now.addingTimeInterval(31 * 86_400)

        let journals = store.journals.map { journal in
            WidgetJournalInfo(
                id: journal.id,
                title: journal.title,
                icon: journal.icon,
                color: journal.color,
                sections: store.sections
                    .filter { $0.journalID == journal.id }
                    .sorted { $0.position < $1.position }
                    .map { WidgetSectionInfo(id: $0.id, title: $0.title) }
            )
        }

        let progress = store.journals.map { journal in
            let result = store.progress(journalID: journal.id, date: today)
            return WidgetJournalProgress(
                journalID: journal.id,
                done: result.done,
                total: result.total,
                note: store.entry(journalID: journal.id, date: today)?.note ?? ""
            )
        }

        let occurrences = store.occurrences(in: DateInterval(start: now.addingTimeInterval(-86_400), end: rangeEnd))
            .filter { !$0.completed }
            .sorted { $0.start < $1.start }
        let ongoing = occurrences.first { $0.start <= now && $0.end > now }
        let future = occurrences.filter { $0.start > now }
        let nextEvent = ongoing ?? future.first

        var checklist: [WidgetChecklistItem] = []
        for journal in store.journals {
            let entry = store.entry(journalID: journal.id, date: today)
            let sections = Dictionary(uniqueKeysWithValues: store.sections.map { ($0.id, $0.title) })
            for field in store.activeFields(in: journal.id) where field.kind == .checkbox {
                let value = store.value(fieldID: field.id, entryID: entry?.id)
                checklist.append(WidgetChecklistItem(
                    fieldID: field.id,
                    journalID: journal.id,
                    title: field.title,
                    icon: field.icon,
                    sectionID: field.sectionID,
                    sectionTitle: field.sectionID.flatMap { sections[$0] },
                    checked: value?.checked ?? false
                ))
            }
        }

        let reminders = NotificationCoordinator.makePlan(
            events: store.events,
            reminders: store.reminders,
            recurrences: store.recurrences,
            exceptions: store.exceptions,
            now: now
        )
        .filter { $0.fireDate >= now && $0.fireDate <= rangeEnd }
        .prefix(4)
        .map {
            WidgetReminderInfo(
                id: $0.id,
                eventID: $0.eventID,
                title: $0.title,
                body: $0.body,
                fireDate: $0.fireDate,
                eventStart: $0.occurrence
            )
        }

        return WidgetSnapshot(
            generatedAt: now,
            displayName: UserDefaults.standard.string(forKey: "displayName") ?? "",
            todayDayKey: SharedDayKey.string(today),
            journals: journals,
            defaultJournalID: journals.first?.id,
            progress: progress,
            nextEvent: nextEvent.map(eventInfo),
            upcoming: future.prefix(6).map(eventInfo),
            reminders: Array(reminders),
            checklist: checklist,
            notificationsEnabled: store.notifications.canDeliver
        )
    }

    private static func eventInfo(_ occurrence: EventOccurrence) -> WidgetEventInfo {
        WidgetEventInfo(
            id: occurrence.id,
            eventID: occurrence.event.id,
            title: occurrence.event.title,
            start: occurrence.start,
            end: occurrence.end,
            allDay: occurrence.event.allDay,
            timeZoneID: occurrence.event.timeZoneID,
            color: occurrence.event.color,
            icon: occurrence.event.icon,
            location: occurrence.event.location,
            isRecurring: occurrence.isRecurring,
            completed: occurrence.completed,
            journalEntryID: occurrence.event.journalEntryID
        )
    }
}
