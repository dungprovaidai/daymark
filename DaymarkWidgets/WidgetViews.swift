import SwiftUI
import WidgetKit

enum DaymarkWidgetStyle {
    case overview, agenda, nextEvent
}

struct DaymarkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: DaymarkWidgetEntry
    let style: DaymarkWidgetStyle

    private var accent: Color { WidgetPalette.accent(colorScheme) }
    private var todayLink: URL { DaymarkDeepLink.today(journalID: entry.journal?.id, date: entry.date) }

    var body: some View {
        Group {
            if entry.snapshot.journals.isEmpty {
                emptyState
            } else {
                switch family {
                case .systemSmall: smallLayout
                case .systemMedium: mediumLayout
                default: largeLayout
                }
            }
        }
        .containerBackground(for: .widget) { DaymarkWidgetBackground() }
        .widgetURL(todayLink)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(accent)
            Text("Open Daymark").font(.headline)
            Text("Your journal and events will appear here after you open the app once.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(4)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(compact: true)
            Spacer(minLength: 0)
            switch style {
            case .agenda:
                upcomingSection(limit: 2, compact: true)
            case .nextEvent:
                nextEventCard(compact: true)
            case .overview:
                HStack(alignment: .center, spacing: 10) {
                    progressRing(size: 40)
                    progressText(compact: true)
                }
                nextEventLine
            }
            footerLink(compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                header(compact: false)
                HStack(spacing: 9) {
                    progressRing(size: 40)
                    progressText(compact: true)
                }
                Spacer(minLength: 0)
                footerLink(compact: true)
            }
            .frame(width: 128, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                switch style {
                case .overview:
                    focusContent(limit: 2)
                case .agenda:
                    upcomingSection(limit: 2, compact: true)
                    remindersSection(limit: 1)
                case .nextEvent:
                    nextEventCard(compact: false)
                    upcomingSection(limit: 1, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                header(compact: false)
                Spacer()
                progressRing(size: 54)
            }
            progressLine
            switch style {
            case .overview:
                focusContent(limit: 3)
                if entry.focus != .checklist, !entry.checklist.isEmpty {
                    checklistSection(limit: 2)
                }
            case .agenda:
                upcomingSection(limit: 4, compact: false)
                remindersSection(limit: 2)
            case .nextEvent:
                nextEventCard(compact: false)
                upcomingSection(limit: 2, compact: true)
            }
            Spacer(minLength: 0)
            footerLink(compact: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func focusContent(limit: Int) -> some View {
        switch entry.focus {
        case .checklist:
            checklistSection(limit: limit)
        case .reminders:
            remindersSection(limit: limit)
        case .agenda:
            upcomingSection(limit: limit, compact: false)
        case .nextEvent:
            nextEventCard(compact: false)
        case .progress:
            progressDetail
        }
    }

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(WidgetFormat.weekday(entry.date).uppercased())
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .tracking(0.7).foregroundStyle(.secondary).lineLimit(1)
            Text(entry.date.formatted(.dateTime.day()))
                .font(.system(size: compact ? 28 : 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(entry.date.formatted(.dateTime.month(.wide)))
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func progressRing(size: CGFloat) -> some View {
        let progress = entry.progress
        let fraction = progress?.fraction ?? 0
        let percent = progress.map { $0.total > 0 ? Int(($0.fraction * 100).rounded()) : 0 } ?? 0
        return ZStack {
            Circle().stroke(accent.opacity(0.16), lineWidth: max(4, size * 0.09))
            Circle().trim(from: 0, to: fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: max(4, size * 0.09), lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Daily progress \(percent) percent")
    }

    private func progressText(compact: Bool) -> some View {
        let progress = entry.progress
        return VStack(alignment: .leading, spacing: 2) {
            Text(progress?.total == 0 ? "A fresh page" : "\(progress?.done ?? 0) of \(progress?.total ?? 0)")
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .lineLimit(1)
            Text("fields complete")
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var progressLine: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.journal?.title ?? "Journal").font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(entry.progress?.done ?? 0)/\(entry.progress?.total ?? 0)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: entry.progress?.fraction ?? 0).tint(accent)
        }
    }

    private var progressDetail: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Today’s journal").font(.subheadline.weight(.semibold))
            Text(entry.progress?.total == 0
                 ? "Add a field in Daymark to begin tracking your rhythm."
                 : "\(entry.progress?.done ?? 0) of \(entry.progress?.total ?? 0) fields complete. Every small entry counts.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    private var nextEventLine: some View {
        Group {
            if let event = entry.snapshot.nextEvent {
                Link(destination: event.deepLink) {
                    HStack(spacing: 6) {
                        Image(systemName: event.icon).font(.caption2).foregroundStyle(WidgetPalette.color(event.color, scheme: colorScheme))
                        Text(event.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(WidgetFormat.time(event.start, timeZoneID: event.timeZoneID, allDay: event.allDay))
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                Text("No upcoming events").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func nextEventCard(compact: Bool) -> some View {
        Group {
            if let event = entry.snapshot.nextEvent {
                Link(destination: event.deepLink) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: event.icon)
                                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                                .foregroundStyle(WidgetPalette.color(event.color, scheme: colorScheme))
                            Text(event.isRecurring ? "REPEATING" : "NEXT UP")
                                .font(.system(size: 8, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(.secondary)
                        }
                        Text(event.title)
                            .font(.system(size: compact ? 12 : 15, weight: .semibold))
                            .foregroundStyle(.primary).lineLimit(compact ? 1 : 2)
                        Text(WidgetFormat.eventLine(event))
                            .font(.system(size: compact ? 10 : 11))
                            .foregroundStyle(.secondary).lineLimit(1)
                        if !event.location.isEmpty, !compact {
                            Label(event.location, systemImage: "location")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("An open calendar").font(.system(size: 12, weight: .semibold))
                    Text("A little breathing room.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func upcomingSection(limit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            sectionLabel("Upcoming")
            if entry.snapshot.upcoming.isEmpty {
                Text("Nothing scheduled.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.snapshot.upcoming.prefix(limit))) { event in
                    Link(destination: event.deepLink) {
                        HStack(spacing: 6) {
                            Circle().fill(WidgetPalette.color(event.color, scheme: colorScheme))
                                .frame(width: 5, height: 5)
                            Text(event.title).font(.system(size: compact ? 10 : 11, weight: .medium))
                                .foregroundStyle(.primary).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(WidgetFormat.eventLine(event)).font(.system(size: 9))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func remindersSection(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Reminders")
            if !entry.snapshot.notificationsEnabled {
                Link(destination: DaymarkDeepLink.settings) {
                    Text("Notifications are off. Open Daymark to enable them.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
            } else if entry.snapshot.reminders.isEmpty {
                Text("No reminders queued.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.snapshot.reminders.prefix(limit))) { reminder in
                    Link(destination: DaymarkDeepLink.event(eventID: reminder.eventID, start: reminder.eventStart)) {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(accent)
                            Text(reminder.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(WidgetFormat.reminderLine(reminder)).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func checklistSection(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Checklist")
            let items = entry.checklist.sorted { !$0.checked && $1.checked }
            if items.isEmpty {
                Text("No checklist fields for today.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.prefix(limit))) { item in
                    Button(intent: ToggleChecklistIntent(
                        fieldID: item.fieldID,
                        journalID: item.journalID,
                        dayKey: entry.snapshot.todayDayKey,
                        checked: item.checked
                    )) {
                        HStack(spacing: 7) {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(item.checked ? WidgetPalette.color("mint", scheme: colorScheme) : Color.secondary)
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(item.checked ? .secondary : .primary)
                                .strikethrough(item.checked)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.checked ? "Completed" : "Not completed")
                }
            }
        }
    }

    private func footerLink(compact: Bool) -> some View {
        Link(destination: todayLink) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill").font(.system(size: compact ? 9 : 10))
                Text("Open today").font(.system(size: compact ? 9 : 10, weight: .medium))
            }
            .foregroundStyle(accent)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .semibold)).tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct DaymarkLockScreenView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: DaymarkWidgetEntry

    private var progress: WidgetJournalProgress? { entry.progress }
    private var percent: Int { progress.map { $0.total > 0 ? Int(($0.fraction * 100).rounded()) : 0 } ?? 0 }
    private var todayLink: URL { DaymarkDeepLink.today(journalID: entry.journal?.id, date: entry.date) }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("\(percent)% · \(entry.snapshot.nextEvent?.title ?? "Daymark")")
                    .lineLimit(1)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Circle().stroke(.secondary.opacity(0.25), lineWidth: 4)
                    Circle().trim(from: 0, to: progress?.fraction ?? 0)
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                    Text("\(percent)%").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                }
            default:
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.caption2.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(percent)%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress?.fraction ?? 0).tint(WidgetPalette.accent(colorScheme))
                    if let next = entry.snapshot.nextEvent {
                        Text("Next · \(next.title)").font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                    } else {
                        Text("A quiet day ahead").font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .widgetURL(todayLink)
    }
}
