import SwiftUI
import UserNotifications

struct EventEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var editingReminder: ReminderSpec?
    @State private var confirmSeriesReset = false
    private let original: EventOccurrence?
    private let entireSeries: Bool

    init(date: Date) { _draft = State(initialValue: EventDraft(date: date)); original = nil; entireSeries = false }
    @MainActor init(occurrence: EventOccurrence, entireSeries: Bool, store: DaymarkStore) {
        original = occurrence; self.entireSeries = entireSeries
        _draft = State(initialValue: EventDraft(occurrence: occurrence, store: store, entireSeries: entireSeries))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event title", text: $draft.title).font(.title3.weight(.medium)).accessibilityLabel("Event title, required")
                    TextField("Description", text: $draft.details, axis: .vertical).lineLimit(2...5)
                } header: { Text("Make a little time") }
                Section {
                    Toggle("All day", isOn: $draft.allDay).onChange(of: draft.allDay) { _, value in draft.setAllDay(value) }
                    DatePicker("Starts", selection: $draft.start, displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker(draft.allDay ? "Last day" : "Ends", selection: $draft.end,
                               displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                    NavigationLink {
                        TimeZonePicker(selection: $draft.timeZoneID)
                    } label: {
                        LabeledContent("Time zone", value: draft.timeZoneID.replacingOccurrences(of: "_", with: " "))
                    }
                } header: { Text("When") } footer: {
                    Text(draft.allDay ? "The last day is included. All-day dates use the selected time zone." : "Repeating events keep this local time in the selected time zone, including daylight-saving changes.")
                }
                .environment(\.timeZone, TimeZone(identifier: draft.timeZoneID) ?? .current)
                Section("Details") {
                    TextField("Location (optional)", text: $draft.location)
                    Picker("Category", selection: $draft.category) {
                        ForEach(EventCategory.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }.onChange(of: draft.category) { _, category in draft.color = category.color; draft.icon = category.icon }
                    ColorPickerRow(selection: $draft.color)
                    DisclosureGroup("Icon") { IconPicker(selection: $draft.icon) }
                    Toggle("Completed", isOn: $draft.completed)
                }
                if original?.isRecurring != true || entireSeries { recurrenceSection }
                else { Section { Label("Editing only this occurrence", systemImage: "repeat").foregroundStyle(.secondary) } }
                reminderSection
                Section {
                    NotificationPermissionView()
                }
                Section("A little more context") {
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                    Picker("Journal entry", selection: $draft.journalEntryID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(store.entries) { entry in
                            Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(store.journals.first { $0.id == entry.journalID }?.title ?? "Journal")")
                                .tag(Optional(entry.id))
                        }
                    }
                }
                if let validation = draft.validation { Section { Text(validation).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle(original == nil ? "New event" : "Edit event").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { attemptSave() }.bold().disabled(draft.validation != nil) }
            }
            .sheet(item: $editingReminder) { reminder in
                ReminderEditor(initial: reminder, existing: draft.reminders) { spec in
                    if let index = draft.reminders.firstIndex(where: { $0.id == spec.id }) { draft.reminders[index] = spec }
                    else { draft.reminders.append(spec) }
                }
            }
            .confirmationDialog("Update the series schedule?", isPresented: $confirmSeriesReset, titleVisibility: .visible) {
                Button("Update series", role: .destructive) { save() }
            } message: {
                Text("Changing the dates or repeat rule resets individual edits, skipped dates, and completion overrides in this series. All occurrences will follow the new schedule.")
            }
        }
    }

    private var recurrenceSection: some View {
        Section {
            Toggle("Repeat", isOn: $draft.repeats)
            if draft.repeats {
                Picker("Frequency", selection: $draft.rule.frequency) {
                    ForEach(RecurrenceFrequency.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Every \(draft.rule.interval) \(draft.rule.frequency.unit)\(draft.rule.interval == 1 ? "" : "s")", value: $draft.rule.interval, in: 1...99)
                if draft.rule.frequency == .weekly {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On these days").font(.subheadline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 4) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                let selected = draft.rule.weekdays.contains(day)
                                Button {
                                    if selected { draft.rule.weekdays.removeAll { $0 == day } } else { draft.rule.weekdays.append(day) }
                                    Feedback.tap()
                                } label: {
                                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1]).font(.subheadline.weight(.medium))
                                        .frame(width: 42, height: 44)
                                        .background(selected ? Palette.accent : Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                        .foregroundStyle(selected ? Color.white : Palette.accent)
                                }.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                        if draft.rule.weekdays.isEmpty { Text("Uses the start date’s weekday.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                Toggle("End repeat", isOn: Binding(get: { draft.rule.until != nil }, set: {
                    draft.rule.until = $0 ? draft.calendar.date(byAdding: .month, value: 1, to: draft.start) : nil
                }))
                if draft.rule.until != nil {
                    DatePicker("Through", selection: Binding(get: { draft.rule.until ?? draft.start }, set: { draft.rule.until = $0 }), displayedComponents: .date)
                }
            }
        } header: { Text("Repeat") } footer: {
            if draft.repeats && (draft.rule.frequency == .monthly || draft.rule.frequency == .yearly) {
                Text("Dates that don’t exist are skipped. For example, a monthly event on the 31st skips February.")
            }
        }
    }
    private var reminderSection: some View {
        Section {
            ForEach(draft.reminders) { reminder in
                Button { editingReminder = reminder } label: {
                    HStack {
                        Label(reminder.label, systemImage: "bell").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }.swipeActions { Button("Delete", role: .destructive) { draft.reminders.removeAll { $0.id == reminder.id } } }
            }
            .onDelete { draft.reminders.remove(atOffsets: $0) }
            Menu {
                ForEach(ReminderSpec.presets) { preset in
                    Button(preset.label) { draft.reminders.append(ReminderSpec(amount: preset.amount, unit: preset.unit)) }
                        .disabled(draft.reminders.contains { $0.equivalenceKey == preset.equivalenceKey })
                }
                Divider()
                Button("Custom…") { editingReminder = ReminderSpec(amount: 10, unit: .minutes) }
            } label: { Label("Add reminder", systemImage: "plus.circle") }
        } header: { Text("Reminders") } footer: {
            Text("Tap a reminder to edit it, or swipe to remove it. All-day reminders are relative to midnight in the event’s time zone. Reminders in the past won’t be sent.")
        }
    }
    private func attemptSave() {
        if let original, original.isRecurring, entireSeries,
           draft.scheduleChanged(from: original.event, rule: store.schedule(for: original.event).rule),
           store.exceptions.contains(where: { $0.eventID == original.event.id }) {
            confirmSeriesReset = true
        } else { save() }
    }
    private func save() {
        if draft.allDay { draft.start = draft.calendar.startOfDay(for: draft.start) }
        if store.saveEvent(draft, original: original, entireSeries: entireSeries) { dismiss() }
    }
}

struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spec: ReminderSpec
    let existing: [ReminderSpec]
    let onSave: (ReminderSpec) -> Void
    private var duplicate: Bool { existing.contains { $0.id != spec.id && $0.equivalenceKey == spec.equivalenceKey } }
    init(initial: ReminderSpec, existing: [ReminderSpec], onSave: @escaping (ReminderSpec) -> Void) {
        _spec = State(initialValue: initial); self.existing = existing; self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Amount", selection: $spec.amount) {
                        ForEach(0...365, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Unit", selection: $spec.unit) { ForEach(ReminderUnit.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                } footer: { Text(duplicate ? "This reminder is already on the event." : spec.label) }
            }.navigationTitle("Custom reminder").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { onSave(spec); dismiss() }.bold().disabled(duplicate) }
                }
        }.presentationDetents([.medium, .large])
    }
}

struct NotificationPermissionView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A gentle nudge, right on time", systemImage: "bell.badge").font(.headline)
            switch store.notifications.authorization {
            case .notDetermined:
                Text("Daymark can remind you about your events with a notification and sound. You choose which events and when.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Enable notifications") {
                    Task { await store.notifications.requestPermission(); store.reschedule() }
                }.buttonStyle(.borderedProminent)
            case .denied:
                Text("Notifications are off. Your reminders are saved, but iOS won’t deliver them until you allow notifications in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            default:
                Label("Notifications enabled", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.color("mint"))
                Text("Focus and iOS notification settings may silence alerts.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8).task { await store.notifications.refreshPermission() }
    }
}

struct TimeZonePicker: View {
    @Binding var selection: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    private var zones: [String] { TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: "_")) } }
    var body: some View {
        List {
            Button("Use current: \(TimeZone.current.identifier)") { selection = TimeZone.current.identifier; dismiss() }
            ForEach(zones, id: \.self) { zone in
                Button { selection = zone; dismiss() } label: {
                    HStack { Text(zone.replacingOccurrences(of: "_", with: " ")); Spacer(); if zone == selection { Image(systemName: "checkmark") } }
                }.foregroundStyle(.primary)
            }
        }.searchable(text: $search).navigationTitle("Time zone")
    }
}
