import SwiftUI

enum TodaySection: String, CaseIterable, Identifiable {
    case journal, schedule, habits, insights
    var id: String { rawValue }
    var title: String {
        switch self {
        case .journal: return "Journal"
        case .schedule: return "Schedule & reminders"
        case .habits: return "Habits"
        case .insights: return "A little perspective"
        }
    }
    var icon: String {
        switch self {
        case .journal: return "book.closed"
        case .schedule: return "calendar"
        case .habits: return "leaf"
        case .insights: return "chart.xyaxis.line"
        }
    }
    var detail: String {
        switch self {
        case .journal: return "Today’s progress, reflection, and writing shortcut."
        case .schedule: return "Today’s events and the next reminder."
        case .habits: return "The habits you’re keeping today."
        case .insights: return "A few real numbers from your recent days."
        }
    }
}

enum TodayLayout {
    static func visible(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        var seen = Set<TodaySection>()
        var ordered = orderRaw.split(separator: ",").compactMap { TodaySection(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        for section in TodaySection.allCases where !seen.contains(section) { ordered.append(section) }
        return ordered.filter { !hidden.contains($0.rawValue) }
    }

    static func hidden(orderRaw: String, hiddenRaw: String) -> [TodaySection] {
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        return TodaySection.allCases.filter { hidden.contains($0.rawValue) }
    }
}

struct TodayJournalCard: View {
    @Environment(DaymarkStore.self) private var store
    let journal: Journal?
    let progress: (done: Int, total: Int)
    let note: String
    let onOpen: () -> Void

    private var fraction: Double { progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total) }
    private var completed: Bool { progress.total > 0 && progress.done == progress.total }

    var body: some View {
        Button(action: onOpen) {
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeading(title: "Today’s journal", subtitle: journal?.title ?? "A place for your day")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    }
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 6)
                            Circle().trim(from: 0, to: fraction).stroke(Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                                .font(.headline.weight(.bold)).monospacedDigit()
                        }.frame(width: 62, height: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(completed ? "A day well recorded" : progress.total == 0 ? "A fresh page" : "\(progress.done) of \(progress.total) fields complete")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(note.isEmpty ? "A little reflection is waiting for you." : note)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    if progress.total > 0 { ProgressView(value: fraction).tint(Palette.accent) }
                }
            }
        }.buttonStyle(PressStyle())
            .accessibilityLabel("Open today’s journal")
            .accessibilityValue("\(progress.done) of \(progress.total) fields complete")
    }
}

struct TodayScheduleCard: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.openURL) private var openURL
    let events: [EventOccurrence]
    let onOpenCalendar: () -> Void
    let onOpenEvent: (EventOccurrence) -> Void

    private var nextUpcoming: EventOccurrence? {
        let end = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        return store.occurrences(in: DateInterval(start: .now, end: end)).first { $0.start > .now && !$0.completed }
    }
    private var nextReminder: PlannedNotification? {
        NotificationCoordinator.makePlan(events: store.events, reminders: store.reminders, recurrences: store.recurrences, exceptions: store.exceptions)
            .first { $0.fireDate > .now }
    }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(title: "On your day", subtitle: events.isEmpty ? "A little breathing room" : "\(events.count) thing\(events.count == 1 ? "" : "s")")
                    Spacer()
                    Button("Calendar", action: onOpenCalendar).font(.subheadline.weight(.medium))
                }
                if events.isEmpty {
                    HStack(spacing: 12) {
                        SymbolTile(symbol: "sparkles", color: Palette.color("mint"))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nothing scheduled").font(.subheadline.weight(.medium))
                            Text("Space for the unexpected.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(Array(events.prefix(4))) { occurrence in
                        Button { onOpenEvent(occurrence) } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2).fill(Palette.color(occurrence.event.color)).frame(width: 3, height: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(occurrence.event.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text(EventFormatting.interval(occurrence)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                    }
                }
                if let nextUpcoming, !events.contains(where: { $0.id == nextUpcoming.id }) {
                    Divider()
                    Button { onOpenEvent(nextUpcoming) } label: {
                        HStack {
                            Label("Next up · \(nextUpcoming.event.title)", systemImage: "arrow.right.circle")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(EventFormatting.interval(nextUpcoming, includeDate: true)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }.buttonStyle(PressStyle())
                }
                if let nextReminder {
                    Divider()
                    if store.notifications.canDeliver {
                        Label("Next reminder · \(nextReminder.title) at \(nextReminder.fireDate.formatted(date: .omitted, time: .shortened))", systemImage: "bell")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label("Notifications are off · Open Settings", systemImage: "bell.slash").font(.caption).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct TodayHabitsCard: View {
    @Environment(DaymarkStore.self) private var store
    let habits: [Habit]
    let completed: Int
    let total: Int
    let onOpenHabits: () -> Void
    let onToggle: (Habit) -> Void

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(title: "Habits", subtitle: total == 0 ? "A gentle rhythm" : "\(completed) of \(total) complete")
                    Spacer()
                    Button("All habits", action: onOpenHabits).font(.subheadline.weight(.medium))
                }
                if habits.isEmpty {
                    HStack(spacing: 12) {
                        SymbolTile(symbol: "leaf", color: Palette.color("mint"))
                        Text("No habits scheduled today. Add one when you’re ready.").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(habits) { habit in
                        HStack(spacing: 10) {
                            SymbolTile(symbol: habit.icon, color: Palette.color(habit.color))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(habit.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(habit.frequencyDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button { onToggle(habit) } label: {
                                Image(systemName: store.isHabitComplete(habit, on: .now) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(store.isHabitComplete(habit, on: .now) ? Palette.color("mint") : Palette.accent.opacity(0.55))
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(PressStyle())
                                .accessibilityLabel(store.isHabitComplete(habit, on: .now) ? "Mark \(habit.name) incomplete" : "Complete \(habit.name)")
                        }
                    }
                    if total > habits.count {
                        Text("\(total - habits.count) more habit\(total - habits.count == 1 ? "" : "s") today").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TodayInsightsCard: View {
    @Environment(DaymarkStore.self) private var store
    let today: Date
    let onOpenInsights: () -> Void

    private var entries30: Int {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today
        return store.entries.filter { $0.date >= start }.count
    }
    private var journalStreak: Int {
        let days = Set(store.entries.map(\.dayKey))
        var date = Calendar.current.startOfDay(for: today)
        if !days.contains(DayKey.string(date)) { date = Calendar.current.date(byAdding: .day, value: -1, to: date)! }
        var count = 0
        while days.contains(DayKey.string(date)), count < 3_660 {
            count += 1; date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }
    private var habitWeek: Int {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: today) ?? DateInterval(start: today, duration: 1)
        return store.habitCompletions.filter { $0.completed && $0.date >= week.start && $0.date < week.end }.count
    }
    private var upcomingWeek: Int {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        return store.occurrences(in: DateInterval(start: today, end: end)).filter { !$0.completed }.count
    }

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(title: "A little perspective", subtitle: "From your real days")
                    Spacer()
                    Button("Insights", action: onOpenInsights).font(.subheadline.weight(.medium))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    miniStat(value: "\(entries30)", label: "entries in 30 days", icon: "book.closed", color: "lavender")
                    miniStat(value: "\(journalStreak)", label: "day journal streak", icon: "flame", color: "amber")
                    miniStat(value: "\(habitWeek)", label: "habit check-ins this week", icon: "leaf", color: "mint")
                    miniStat(value: "\(upcomingWeek)", label: "events in the next 7 days", icon: "calendar", color: "blue")
                }
            }
        }
    }

    private func miniStat(value: String, label: String, icon: String, color: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(Palette.color(color))
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(10).background(Palette.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TodayCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("todaySectionOrder") private var orderRaw = TodaySection.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("todayHiddenSections") private var hiddenRaw = ""
    private var visible: [TodaySection] { TodayLayout.visible(orderRaw: orderRaw, hiddenRaw: hiddenRaw) }
    private var hidden: [TodaySection] { TodayLayout.hidden(orderRaw: orderRaw, hiddenRaw: hiddenRaw) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visible) { section in
                        HStack(spacing: 12) {
                            Image(systemName: section.icon).foregroundStyle(Palette.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title).font(.headline)
                                Text(section.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { true },
                                set: { isVisible in if !isVisible { hide(section) } }
                            )).labelsHidden()
                        }.padding(.vertical, 3)
                    }.onMove { source, destination in
                        var ordered = visible
                        ordered.move(fromOffsets: source, toOffset: destination)
                        var complete = ordered
                        for section in TodaySection.allCases where !complete.contains(section) && !hidden.contains(section) { complete.append(section) }
                        orderRaw = complete.map(\.rawValue).joined(separator: ",")
                    }
                } header: { Text("Visible") } footer: {
                    Text("Drag to reorder. Turn a section off to hide it without losing any data.")
                }

                if !hidden.isEmpty {
                    Section("Hidden") {
                        ForEach(hidden) { section in
                            Button { show(section) } label: {
                                HStack {
                                    Label(section.title, systemImage: section.icon).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Restore default layout") {
                        orderRaw = TodaySection.allCases.map(\.rawValue).joined(separator: ",")
                        hiddenRaw = ""
                    }
                }
            }.navigationTitle("Customize Today").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }

    private func hide(_ section: TodaySection) {
        var values = hiddenRaw.split(separator: ",").map(String.init)
        if !values.contains(section.rawValue) { values.append(section.rawValue) }
        hiddenRaw = values.joined(separator: ",")
    }

    private func show(_ section: TodaySection) {
        hiddenRaw = hiddenRaw.split(separator: ",").map(String.init).filter { $0 != section.rawValue }.joined(separator: ",")
        var ordered = orderRaw.split(separator: ",").map(String.init)
        if !ordered.contains(section.rawValue) { ordered.append(section.rawValue) }
        orderRaw = ordered.joined(separator: ",")
    }
}
