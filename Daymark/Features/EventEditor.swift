import SwiftUI
import UserNotifications

struct EventEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var editingReminder: ReminderSpec?
    @State private var confirmSeriesReset = false
    @State private var showNotificationExplainer = false
    @State private var offeredNotificationExplainer = false
    private let original: EventOccurrence?
    private let entireSeries: Bool

    init(date: Date) { _draft = State(initialValue: EventDraft(date: date)); original = nil; entireSeries = false }
    init(date: Date, category: EventCategory) {
        var draft = EventDraft(date: date)
        draft.category = category; draft.color = category.color; draft.icon = category.icon
        _draft = State(initialValue: draft); original = nil; entireSeries = false
    }
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
                    else { addReminder(spec) }
                }
            }
            .confirmationDialog("Update the series schedule?", isPresented: $confirmSeriesReset, titleVisibility: .visible) {
                Button("Update series", role: .destructive) { save() }
            } message: {
                Text("Changing the dates or repeat rule resets individual edits, skipped dates, and completion overrides in this series. All occurrences will follow the new schedule.")
            }
            .sheet(isPresented: $showNotificationExplainer, onDismiss: { offeredNotificationExplainer = true }) {
                NotificationExplainerSheet()
            }
        }
    }

    private func addReminder(_ spec: ReminderSpec) {
        draft.reminders.append(spec)
        if !offeredNotificationExplainer, store.notifications.authorization != .authorized,
           store.notifications.authorization != .ephemeral {
            showNotificationExplainer = true
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
                    Button(preset.label) { addReminder(ReminderSpec(amount: preset.amount, unit: preset.unit)) }
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
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A gentle nudge, right on time", systemImage: "bell.badge").font(.headline)
            switch store.notifications.authorization {
            case .notDetermined:
                Text("Daymark can remind you about events, habits, and important dates with a local notification and sound. You choose what gets a reminder and when. Nothing is sent to a server.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("iOS will ask for permission only after you tap the button below.")
                    .font(.caption).foregroundStyle(.tertiary)
                Button {
                    guard !requesting else { return }
                    requesting = true
                    Task {
                        await store.notifications.requestPermission()
                        store.reschedule()
                        store.syncWidgetSnapshot()
                        requesting = false
                    }
                } label: {
                    if requesting { ProgressView() } else { Text("Enable Notifications") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(requesting)
            case .denied:
                Text("Notifications are off. Your reminders are saved, but iOS won’t deliver them until you allow notifications in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Daymark won’t ask again automatically. iOS only shows the system prompt once.")
                    .font(.caption).foregroundStyle(.tertiary)
                Button("Open iOS Settings") { openSettings() }.buttonStyle(.borderedProminent)
            case .provisional:
                Label("Delivered quietly", systemImage: "bell.badge.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.color("mint"))
                Text("iOS has granted provisional permission, so alerts arrive quietly in the Notification Center without banners or sounds. You can change this in iOS Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open iOS Settings") { openSettings() }
            case .authorized:
                Label("Notifications enabled", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.color("mint"))
                Text("Focus, silent mode, and iOS notification settings may still silence alerts.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open iOS Settings") { openSettings() }
            case .ephemeral:
                Label("Temporary permission", systemImage: "clock.badge.checkmark").font(.subheadline).foregroundStyle(Palette.color("mint"))
                Text("This build has temporary notification permission. Open Settings to review the long-term choice.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open iOS Settings") { openSettings() }
            @unknown default:
                Text("Notification permission status is unavailable. Check iOS Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open iOS Settings") { openSettings() }
            }
        }.padding(.vertical, 8)
            .task { await store.notifications.refreshPermission() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await store.notifications.refreshPermission() }
            }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// A clear, user-initiated explanation shown the first time a reminder is added.
struct NotificationExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .font(.system(size: 36)).foregroundStyle(Palette.accent)
                        Text("Reminders, only when you want them").font(.title2.weight(.bold))
                        Text("Daymark uses iOS local notifications. They are created on this device and never sent to a server.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Event reminders arrive before or at the time you choose.", systemImage: "calendar.badge.clock")
                        Label("Habit nudges can arrive at your chosen time each day.", systemImage: "checkmark.circle")
                        Label("You can change or turn off permission in iOS Settings at any time.", systemImage: "gearshape")
                    }.font(.subheadline)
                    NotificationPermissionView()
                    Text("If you choose not to allow notifications now, your reminders stay saved and you can enable them later in Settings.")
                        .font(.caption).foregroundStyle(.tertiary)
                }.padding(20).frame(maxWidth: 600)
            }
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
