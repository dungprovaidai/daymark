import SwiftUI

enum CalendarMode: String, CaseIterable { case month = "Month", week = "Week", day = "Day" }

struct CalendarView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(AppRoute.self) private var route
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = CalendarMode.month
    @State private var showJump = false
    @State private var showAdd = false
    @State private var selectedEvent: EventOccurrence?
    private var calendar: Calendar { .current }
    private var selectedDate: Date { route.calendarDate }
    private var month: DateInterval { calendar.dateInterval(of: .month, for: selectedDate)! }
    private var dayRange: DateInterval { calendar.dateInterval(of: .day, for: selectedDate)! }
    private var selectedEvents: [EventOccurrence] { store.occurrences(in: dayRange) }
    private var journalEntries: [JournalEntry] { store.entries.filter { $0.dayKey == DayKey.string(selectedDate) } }
    private var upcoming: [EventOccurrence] {
        let end = calendar.date(byAdding: .day, value: 90, to: .now)!
        return store.occurrences(in: DateInterval(start: .now, end: end)).filter { $0.start > .now && !$0.completed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Calendar view", selection: $mode) {
                    ForEach(CalendarMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Surface {
                    VStack(spacing: 18) {
                        calendarHeader
                        if mode == .month { monthGrid }
                        else if mode == .week { weekStrip }
                        else {
                            VStack(spacing: 4) {
                                Text(selectedDate.formatted(.dateTime.day())).font(.system(.largeTitle, design: .rounded).weight(.bold))
                                Text(selectedDate.formatted(.dateTime.weekday(.wide))).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        HStack(spacing: 16) {
                            Label { Text("Events") } icon: { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
                            Label { Text("Journal") } icon: { RoundedRectangle(cornerRadius: 1).fill(Palette.color("mint")).frame(width: 5, height: 5) }
                            Spacer()
                            Button("Today") { select(.now) }.fontWeight(.medium)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                SectionHeading(title: calendar.isDateInToday(selectedDate) ? "Today’s schedule" : selectedDate.formatted(.dateTime.month(.abbreviated).day()),
                               subtitle: "\(selectedEvents.count) event\(selectedEvents.count == 1 ? "" : "s") · \(journalEntries.count) journal entr\(journalEntries.count == 1 ? "y" : "ies")")
                if selectedEvents.isEmpty {
                    EmptyCard(symbol: "calendar", title: "A little breathing room", message: "Nothing scheduled for this day. Add an event when you’re ready.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(selectedEvents) { occurrence in
                            EventRow(occurrence: occurrence) { selectedEvent = occurrence }
                        }
                    }
                }
                if !journalEntries.isEmpty {
                    SectionHeading(title: "From your journal")
                    ForEach(journalEntries) { entry in
                        NavigationLink {
                            JournalDayView(date: selectedDate, journalID: entry.journalID).navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Surface {
                                HStack(spacing: 12) {
                                    SymbolTile(symbol: "book.closed", color: Palette.color("mint"))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(store.journals.first { $0.id == entry.journalID }?.title ?? "Journal").font(.headline).foregroundStyle(.primary)
                                        Text(entry.note.isEmpty ? "\(store.values.filter { $0.entryID == entry.id }.count) fields recorded" : entry.note)
                                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }.buttonStyle(PressStyle())
                    }
                }
                HStack {
                    SectionHeading(title: "On the horizon", subtitle: "Upcoming in the next 90 days")
                    Spacer()
                    NavigationLink("See all") { UpcomingEventsView() }.font(.subheadline)
                }
                if upcoming.isEmpty {
                    Text("Your next chapter is open.").font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 20)
                } else {
                    ForEach(Array(upcoming.prefix(5))) { occurrence in EventRow(occurrence: occurrence, showDate: true) { selectedEvent = occurrence } }
                }
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.pageBackground().navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showJump = true } label: { Image(systemName: "calendar.badge.clock") }.accessibilityLabel("Jump to date")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add event")
                }
            }
            .sheet(isPresented: $showAdd) { EventEditor(date: selectedDate) }
            .sheet(item: $selectedEvent) { EventDetailView(occurrence: $0) }
            .sheet(isPresented: $showJump) {
                NavigationStack {
                    DatePicker("Jump to date", selection: Binding(get: { selectedDate }, set: { select($0) }), displayedComponents: .date)
                        .datePickerStyle(.graphical).padding().navigationTitle("Find a day").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showJump = false } } }
                }.presentationDetents([.medium, .large])
            }
            .onChange(of: route.eventID) { _, _ in openNotification() }
            .onAppear { openNotification() }
    }

    private var calendarHeader: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous \(mode.rawValue.lowercased())")
            Spacer(minLength: 0)
            Button { showJump = true } label: { Text(selectedDate.formatted(.dateTime.month(.wide).year())).font(.headline).foregroundStyle(.primary) }
            Spacer(minLength: 0)
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next \(mode.rawValue.lowercased())")
        }.buttonStyle(PressStyle())
    }
    private var monthGrid: some View {
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: selectedDate)!.count
        let slots = ((leading + count + 6) / 7) * 7
        let occurrences = store.occurrences(in: month)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 7) {
            ForEach(0..<7, id: \.self) { index in
                Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                    .font(.caption).foregroundStyle(.secondary).frame(height: 22).accessibilityHidden(true)
            }
            ForEach(0..<slots, id: \.self) { index in
                if index < leading || index >= leading + count { Color.clear.frame(height: 44).accessibilityHidden(true) }
                else {
                    let date = calendar.date(byAdding: .day, value: index - leading, to: month.start)!
                    dayCell(date, occurrences: occurrences)
                }
            }
        }
    }
    private var weekStrip: some View {
        let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate)!
        let occurrences = store.occurrences(in: week)
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: week.start)!
                VStack(spacing: 8) {
                    Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(.secondary)
                    dayCell(date, occurrences: occurrences)
                }.frame(maxWidth: .infinity)
            }
        }
    }
    private func dayCell(_ date: Date, occurrences: [EventOccurrence]) -> some View {
        let range = calendar.dateInterval(of: .day, for: date)!
        let colors = Array(Set(occurrences.filter { $0.start < range.end && $0.end > range.start }.map { $0.event.color })).sorted()
        let hasJournal = store.entries.contains { $0.dayKey == DayKey.string(date) }
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button { select(date) } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day())).font(.body.weight(selected || calendar.isDateInToday(date) ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : calendar.isDateInToday(date) ? Palette.accent : Color.primary)
                    .frame(width: 33, height: 33).background(selected ? Palette.accent : Color.clear, in: Circle())
                HStack(spacing: 3) {
                    ForEach(Array(colors.prefix(3)), id: \.self) { Circle().fill(Palette.color($0)).frame(width: 4, height: 4) }
                    if hasJournal { RoundedRectangle(cornerRadius: 1).fill(Palette.color("mint")).frame(width: 4, height: 4) }
                }.frame(height: 5)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            .accessibilityValue("\(colors.isEmpty ? "No events" : "Has events")\(hasJournal ? ", has journal entry" : "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func select(_ date: Date) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { route.calendarDate = date }
        Feedback.tap()
    }
    private func move(_ amount: Int) {
        let component: Calendar.Component = mode == .month ? .month : mode == .week ? .weekOfYear : .day
        if let next = calendar.date(byAdding: component, value: amount, to: selectedDate) { select(next) }
    }
    private func openNotification() {
        guard let id = route.eventID else { return }
        selectedEvent = selectedEvents.first { $0.event.id == id }
        route.eventID = nil
    }
}

struct EventRow: View {
    @Environment(DaymarkStore.self) private var store
    let occurrence: EventOccurrence
    var showDate = false
    let action: () -> Void
    var body: some View {
        Surface {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.color(occurrence.event.color)).frame(width: 3)
                Button(action: action) {
                    HStack(spacing: 12) {
                        SymbolTile(symbol: occurrence.event.icon, color: Palette.color(occurrence.event.color))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(occurrence.event.title).font(.headline).foregroundStyle(.primary).strikethrough(occurrence.completed)
                            Text(EventFormatting.interval(occurrence, includeDate: showDate)).font(.caption).foregroundStyle(.secondary)
                            if !occurrence.event.location.isEmpty {
                                Label(occurrence.event.location, systemImage: "location").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if occurrence.isRecurring { Label("Repeating", systemImage: "repeat").font(.caption2).foregroundStyle(.secondary) }
                        }.multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(PressStyle())
                Button { store.toggleCompletion(occurrence) } label: {
                    Image(systemName: occurrence.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(occurrence.completed ? Palette.color("mint") : .secondary)
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(occurrence.completed ? "Mark \(occurrence.event.title) incomplete" : "Complete \(occurrence.event.title)")
            }
        }
    }
}

enum EventFormatting {
    static func interval(_ occurrence: EventOccurrence, includeDate: Bool = false) -> String {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: occurrence.event.timeZoneID) ?? .current
        let formatter = DateFormatter(); formatter.timeZone = cal.timeZone
        if occurrence.event.allDay {
            let last = cal.date(byAdding: .day, value: -1, to: occurrence.end) ?? occurrence.end
            formatter.dateStyle = .medium; formatter.timeStyle = .none
            return cal.isDate(occurrence.start, inSameDayAs: last)
                ? (includeDate ? "\(formatter.string(from: occurrence.start)) · All day" : "All day")
                : "\(formatter.string(from: occurrence.start)) – \(formatter.string(from: last)) · All day"
        }
        formatter.timeStyle = .short
        formatter.dateStyle = includeDate || !cal.isDate(occurrence.start, inSameDayAs: occurrence.end) ? .medium : .none
        let text = "\(formatter.string(from: occurrence.start)) – \(formatter.string(from: occurrence.end))"
        return occurrence.event.timeZoneID == TimeZone.current.identifier ? text : "\(text) (\(cal.timeZone.abbreviation() ?? occurrence.event.timeZoneID))"
    }
}

struct UpcomingEventsView: View {
    @Environment(DaymarkStore.self) private var store
    @State private var selected: EventOccurrence?
    var body: some View {
        let end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        let upcoming = store.occurrences(in: .init(start: .now, end: end)).filter { $0.start > .now && !$0.completed }
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("The next 12 months").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if upcoming.isEmpty { EmptyCard(symbol: "calendar", title: "An open calendar", message: "New events will appear here in date order.") }
                ForEach(upcoming) { occurrence in EventRow(occurrence: occurrence, showDate: true) { selected = occurrence } }
            }.padding(20)
        }.pageBackground().navigationTitle("Upcoming")
            .sheet(item: $selected) { EventDetailView(occurrence: $0) }
    }
}

struct EventDetailView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let occurrence: EventOccurrence
    @State private var showEdit = false
    @State private var editScope = false
    @State private var deleteScope = false
    @State private var entireSeries = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        SymbolTile(symbol: occurrence.event.icon, color: Palette.color(occurrence.event.color))
                        Text(occurrence.event.title).font(.title.weight(.bold))
                        Text(EventFormatting.interval(occurrence, includeDate: true)).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                    Label(occurrence.event.category.title, systemImage: occurrence.event.icon)
                    if !occurrence.event.location.isEmpty { Label(occurrence.event.location, systemImage: "location") }
                    if !occurrence.event.details.isEmpty { Text(occurrence.event.details) }
                }
                if !occurrence.event.notes.isEmpty { Section("Notes") { Text(occurrence.event.notes) } }
                Section("Reminders") {
                    let reminders = store.reminders.filter { $0.eventID == occurrence.event.id }
                    if reminders.isEmpty { Text("No reminders").foregroundStyle(.secondary) }
                    ForEach(reminders) { Label($0.spec.label, systemImage: "bell") }
                }
                if let entryID = occurrence.event.journalEntryID, let entry = store.entries.first(where: { $0.id == entryID }) {
                    Section("Linked journal") {
                        NavigationLink(entry.date.formatted(date: .abbreviated, time: .omitted)) {
                            JournalDayView(date: entry.date, journalID: entry.journalID).navigationTitle("Journal")
                        }
                    }
                }
                Section {
                    Button { store.toggleCompletion(occurrence); dismiss() } label: {
                        Label(occurrence.completed ? "Mark incomplete" : "Mark complete", systemImage: "checkmark.circle")
                    }
                    Button("Delete event", role: .destructive) { deleteScope = true }
                }
            }.navigationTitle("Event").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { if occurrence.isRecurring { editScope = true } else { entireSeries = false; showEdit = true } }
                    }
                }
                .confirmationDialog("Edit repeating event", isPresented: $editScope, titleVisibility: .visible) {
                    Button("This occurrence") { entireSeries = false; showEdit = true }
                    Button("Entire series") { entireSeries = true; showEdit = true }
                }
                .confirmationDialog("Delete event?", isPresented: $deleteScope, titleVisibility: .visible) {
                    Button(occurrence.isRecurring ? "This occurrence" : "Delete event", role: .destructive) {
                        store.deleteEvent(occurrence, entireSeries: false); dismiss()
                    }
                    if occurrence.isRecurring {
                        Button("Entire series", role: .destructive) { store.deleteEvent(occurrence, entireSeries: true); dismiss() }
                    }
                } message: { Text("This action removes the selected event and its pending reminders.") }
                .sheet(isPresented: $showEdit, onDismiss: { dismiss() }) { EventEditor(occurrence: occurrence, entireSeries: entireSeries, store: store) }
        }
    }
}
