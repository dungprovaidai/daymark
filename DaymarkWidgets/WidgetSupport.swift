import Foundation
import SwiftUI
import UIKit
import WidgetKit

struct DaymarkWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let configuration: DaymarkWidgetConfigurationIntent
    let kind: String

    var journal: WidgetJournalInfo? {
        snapshot.journal(id: configuration.journal.flatMap { UUID(uuidString: $0.id) })
    }

    var progress: WidgetJournalProgress? {
        journal.flatMap { snapshot.progressForJournal($0.id) }
    }

    var sectionID: UUID? {
        configuration.section.flatMap { UUID(uuidString: $0.id) }
    }

    var checklist: [WidgetChecklistItem] {
        snapshot.checklistItems(journalID: journal?.id, sectionID: sectionID)
    }

    var focus: WidgetInformation {
        configuration.information ?? .progress
    }
}

enum WidgetEntryFactory {
    static func make(kind: String, configuration: DaymarkWidgetConfigurationIntent = DaymarkWidgetConfigurationIntent(), date: Date = .now) -> DaymarkWidgetEntry {
        DaymarkWidgetEntry(
            date: date,
            snapshot: WidgetSnapshotStore.read() ?? .empty,
            configuration: configuration,
            kind: kind
        )
    }

    static func nextRefresh(for entry: DaymarkWidgetEntry) -> Date {
        let now = Date()
        var candidates = [now.addingTimeInterval(30 * 60)]
        if let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) {
            candidates.append(midnight)
        }
        if let next = entry.snapshot.nextEvent {
            candidates.append(next.start.addingTimeInterval(60))
        }
        if let reminder = entry.snapshot.reminders.first {
            candidates.append(reminder.fireDate.addingTimeInterval(60))
        }
        return candidates.filter { $0 > now }.min() ?? now.addingTimeInterval(30 * 60)
    }
}

struct DaymarkTimelineProvider: AppIntentTimelineProvider {
    let kind: String

    func placeholder(in context: Context) -> DaymarkWidgetEntry {
        WidgetEntryFactory.make(kind: kind)
    }

    func snapshot(for configuration: DaymarkWidgetConfigurationIntent, in context: Context) async -> DaymarkWidgetEntry {
        WidgetEntryFactory.make(kind: kind, configuration: configuration)
    }

    func timeline(for configuration: DaymarkWidgetConfigurationIntent, in context: Context) async -> Timeline<DaymarkWidgetEntry> {
        let entry = WidgetEntryFactory.make(kind: kind, configuration: configuration)
        return Timeline(entries: [entry], policy: .after(WidgetEntryFactory.nextRefresh(for: entry)))
    }
}

struct DaymarkLockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaymarkWidgetEntry {
        WidgetEntryFactory.make(kind: DaymarkShared.kindLockScreen)
    }

    func getSnapshot(in context: Context, completion: @escaping (DaymarkWidgetEntry) -> Void) {
        completion(WidgetEntryFactory.make(kind: DaymarkShared.kindLockScreen))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaymarkWidgetEntry>) -> Void) {
        let entry = WidgetEntryFactory.make(kind: DaymarkShared.kindLockScreen)
        completion(Timeline(entries: [entry], policy: .after(WidgetEntryFactory.nextRefresh(for: entry))))
    }
}

enum WidgetPalette {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.67, green: 0.59, blue: 0.96)
            : Color(red: 0.44, green: 0.34, blue: 0.79)
    }

    static func color(_ name: String, scheme: ColorScheme) -> Color {
        switch name {
        case "mint": return Color(red: 0.16, green: 0.57, blue: 0.44)
        case "blue": return Color(red: 0.23, green: 0.48, blue: 0.78)
        case "amber": return Color(red: 0.78, green: 0.45, blue: 0.13)
        case "rose": return Color(red: 0.76, green: 0.32, blue: 0.46)
        default: return accent(scheme)
        }
    }
}

enum WidgetFormat {
    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func time(_ date: Date, timeZoneID: String, allDay: Bool) -> String {
        if allDay { return "All day" }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func eventLine(_ event: WidgetEventInfo) -> String {
        let time = time(event.start, timeZoneID: event.timeZoneID, allDay: event.allDay)
        guard !Calendar.current.isDateInToday(event.start) else { return time }
        return "\(monthDay(event.start)) · \(time)"
    }

    static func reminderLine(_ reminder: WidgetReminderInfo) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: reminder.fireDate)
    }
}

struct DaymarkWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        LinearGradient(
            colors: [
                WidgetPalette.accent(colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.14),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
