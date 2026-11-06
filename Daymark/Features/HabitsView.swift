import SwiftUI

struct HabitsView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(AppRoute.self) private var route
    @State private var showAdd = false
    @State private var editingHabit: Habit?
    @State private var selectedHabit: Habit?
    @State private var showArchived = false

    private var habits: [Habit] { store.activeHabits }
    private var doneToday: Int { habits.filter { store.isHabitComplete($0, on: .now) }.count }
    private var progress: Double { habits.isEmpty ? 0 : Double(doneToday) / Double(habits.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Small steps, kept close.").font(.title2.weight(.bold))
                    Text("A gentle rhythm for the things that matter.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)

                Surface {
                    HStack(spacing: 20) {
                        HabitProgressRing(fraction: progress, size: 76)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(habits.isEmpty ? "Start with one small thing" : doneToday == habits.count ? "A full-hearted day" : "Your rhythm today")
                                .font(.headline)
                            Text(habits.isEmpty ? "Create a habit you can return to." : "\(doneToday) of \(habits.count) habits complete")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let best = habits.map({ store.habitStats($0).currentStreak }).max(), best > 0 {
                                Label("\(best) day streak", systemImage: "flame.fill").font(.caption).foregroundStyle(Palette.color("amber"))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                if habits.isEmpty {
                    EmptyCard(symbol: "leaf", title: "A little room to grow", message: "Habits are simply promises you keep to yourself. Make the first one small and kind.")
                    Button { showAdd = true } label: { Label("Create a habit", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    HStack {
                        SectionHeading(title: "Today", subtitle: "\(doneToday) complete · \(habits.count - doneToday) remaining")
                        Spacer()
                        Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .accessibilityLabel("New habit")
                    }
                    VStack(spacing: 12) {
                        ForEach(habits) { habit in
                            HabitCard(habit: habit) { selectedHabit = habit } onEdit: { editingHabit = habit }
                        }
                    }
                }

                if !store.habits.filter(\.archived).isEmpty {
                    Button { showArchived = true } label: {
                        HStack {
                            Label("Archived habits", systemImage: "archivebox")
                            Spacer()
                            Text("\(store.habits.filter(\.archived).count)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }.buttonStyle(.plain).font(.subheadline).padding(.top, 4)
                }
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.pageBackground().navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { route.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("New habit")
                }
            }
            .sheet(isPresented: $showAdd) { HabitEditor() }
            .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
            .sheet(item: $selectedHabit) { HabitDetailView(habit: $0) }
            .sheet(isPresented: $showArchived) { ArchivedHabitsView() }
            .onAppear { openRouteHabit() }
            .onChange(of: route.habitID) { _, _ in openRouteHabit() }
    }

    private func openRouteHabit() {
        guard let id = route.habitID, let habit = store.habit(withID: id) else { return }
        selectedHabit = habit
        route.habitID = nil
    }
}

private struct HabitCard: View {
    @Environment(DaymarkStore.self) private var store
    let habit: Habit
    let onOpen: () -> Void
    let onEdit: () -> Void

    private var stats: HabitStats { store.habitStats(habit) }
    private var accent: Color { Palette.color(habit.color) }

    var body: some View {
        Surface {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        SymbolTile(symbol: habit.icon, color: accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(habit.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(habit.frequencyDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if stats.currentStreak > 0 {
                                    Label("\(stats.currentStreak)", systemImage: "flame.fill")
                                        .font(.caption2.weight(.semibold)).foregroundStyle(Palette.color("amber"))
                                }
                            }
                            if habit.frequency == .weekly || habit.frequency == .monthly {
                                ProgressView(value: Double(stats.periodProgress), total: Double(max(1, stats.periodTarget)))
                                    .tint(accent).accessibilityLabel("\(stats.periodProgress) of \(stats.periodTarget) this period")
                                Text("\(stats.periodProgress) of \(stats.periodTarget) · \(stats.periodLabel.lowercased())")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if habit.kind != .checkmark {
                                ProgressView(value: min(1, stats.todayValue / max(0.0001, stats.todayTarget)))
                                    .tint(accent)
                                Text("\(stats.todayValue.compact) / \(stats.todayTarget.compact) \(habit.unit)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if !stats.scheduledToday {
                                Text("Not scheduled today").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(PressStyle())

                if habit.kind == .counter || habit.kind == .duration {
                    Button {
                        store.incrementHabit(habit); Feedback.tap()
                    } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 40, height: 44)
                            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(PressStyle()).accessibilityLabel("Add \(habit.step.compact) \(habit.unit) to \(habit.name)")
                }
                Button {
                    store.toggleHabit(habit)
                } label: {
                    Image(systemName: stats.completedToday ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(stats.completedToday ? Palette.color("mint") : accent.opacity(0.55))
                        .frame(width: 44, height: 44)
                }.buttonStyle(PressStyle())
                    .accessibilityLabel(stats.completedToday ? "Mark \(habit.name) incomplete" : "Complete \(habit.name)")
            }
        }
        .contextMenu {
            Button("Edit habit", systemImage: "pencil") { onEdit() }
            Button(habit.archived ? "Unarchive" : "Archive", systemImage: "archivebox") { store.setHabitArchived(habit, archived: !habit.archived) }
        }
    }
}

struct HabitProgressRing: View {
    let fraction: Double
    var size: CGFloat = 74
    var color: Color = Palette.accent
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: 7)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: size * 0.22, weight: .bold, design: .rounded)).monospacedDigit()
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct HabitEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let habit: Habit?
    @State private var name: String
    @State private var details: String
    @State private var icon: String
    @State private var color: String
    @State private var kind: HabitKind
    @State private var target: Double
    @State private var step: Double
    @State private var unit: String
    @State private var frequency: HabitFrequency
    @State private var weekdays: [Int]
    @State private var periodTarget: Int
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var archived: Bool
    @State private var validation: String?
    @State private var showPermissionExplainer = false
    @State private var saved = false

    private static let dayOrder = [2, 3, 4, 5, 6, 7, 1]
    private static let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    init(habit: Habit? = nil) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _details = State(initialValue: habit?.details ?? "")
        _icon = State(initialValue: habit?.icon ?? "leaf")
        _color = State(initialValue: habit?.color ?? "mint")
        _kind = State(initialValue: habit?.kind ?? .checkmark)
        _target = State(initialValue: habit?.target ?? 1)
        _step = State(initialValue: habit?.step ?? 1)
        _unit = State(initialValue: habit?.unit ?? "")
        _frequency = State(initialValue: habit?.frequency ?? .daily)
        _weekdays = State(initialValue: habit?.weekdays ?? [2, 3, 4, 5, 6, 7, 1])
        _periodTarget = State(initialValue: habit?.periodTarget ?? 3)
        _reminderEnabled = State(initialValue: habit?.reminderEnabled ?? false)
        let hour = habit?.reminderHour ?? 9, minute = habit?.reminderMinute ?? 0
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now)
        _startDate = State(initialValue: habit?.startDate ?? Calendar.current.startOfDay(for: .now))
        _hasEndDate = State(initialValue: habit?.endDate != nil)
        _endDate = State(initialValue: habit?.endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _archived = State(initialValue: habit?.archived ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The habit") {
                    TextField("Name", text: $name)
                    TextField("A note to yourself (optional)", text: $details, axis: .vertical).lineLimit(2...4)
                    IconPicker(selection: $icon)
                    ColorPickerRow(selection: $color)
                }
                Section("How you record it") {
                    Picker("Type", selection: $kind) {
                        ForEach(HabitKind.allCases) { Text($0.title).tag($0) }
                    }
                    if kind != .checkmark {
                        HStack {
                            Text(kind == .duration ? "Minutes" : "Target")
                            Spacer()
                            TextField("Target", value: $target, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90)
                        }
                        HStack {
                            Text("Step")
                            Spacer()
                            TextField("Step", value: $step, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(width: 90)
                        }
                        TextField("Unit (optional)", text: $unit)
                    }
                }
                Section("When") {
                    Picker("Schedule", selection: $frequency) {
                        ForEach(HabitFrequency.allCases) { Text($0.title).tag($0) }
                    }
                    Text(frequency.explanation).font(.caption).foregroundStyle(.secondary)
                    if frequency == .custom {
                        HStack(spacing: 6) {
                            ForEach(Array(Self.dayOrder.enumerated()), id: \.element) { index, day in
                                Button {
                                    if weekdays.contains(day) { weekdays.removeAll { $0 == day } } else { weekdays.append(day) }
                                    Feedback.tap()
                                } label: {
                                    Text(Self.dayLabels[index]).font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(weekdays.contains(day) ? Palette.accent : Palette.accent.opacity(0.08),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(weekdays.contains(day) ? .white : .primary)
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                                    .accessibilityAddTraits(weekdays.contains(day) ? .isSelected : [])
                            }
                        }
                    }
                    if frequency == .weekly || frequency == .monthly {
                        Stepper("Target: \(periodTarget) per \(frequency == .weekly ? "week" : "month")", value: $periodTarget, in: 1...31)
                    }
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Toggle("Set an end date", isOn: $hasEndDate)
                    if hasEndDate { DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date) }
                }
                Section {
                    Toggle(isOn: $reminderEnabled) { Label("Gentle reminder", systemImage: "bell") }
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        Text("A repeating local notification at this time. Daymark will ask for notification permission only when you choose to enable it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Reminder") } footer: {
                    Text("Reminders are scheduled by iOS on this device. Focus, silent mode, and notification settings can affect delivery.")
                }
                if let habit {
                    Section {
                        Toggle("Archive habit", isOn: $archived)
                        Button("Delete habit", role: .destructive) {
                            store.deleteHabit(habit); dismiss()
                        }
                    }
                }
                if let validation { Section { Text(validation).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(habit == nil ? "New habit" : "Edit habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }
            .sheet(isPresented: $showPermissionExplainer, onDismiss: { if saved { dismiss() } }) {
                NotificationExplainerSheet()
            }
        }
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { validation = "Give your habit a name."; return }
        if kind != .checkmark && target <= 0 { validation = "Choose a target greater than zero."; return }
        if frequency == .custom && weekdays.isEmpty { validation = "Choose at least one day."; return }
        let targetHabit = habit ?? Habit(name: clean)
        let isNew = habit == nil
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: reminderTime)
        let success = store.perform {
            if isNew { store.context.insert(targetHabit) }
            targetHabit.name = clean
            targetHabit.details = details
            targetHabit.icon = icon
            targetHabit.color = color
            targetHabit.kindRaw = kind.rawValue
            targetHabit.target = kind == .checkmark ? 1 : max(0.01, target)
            targetHabit.step = max(0.01, step)
            targetHabit.unit = kind == .duration && unit.trimmingCharacters(in: .whitespaces).isEmpty ? "minutes" : unit
            targetHabit.frequencyRaw = frequency.rawValue
            targetHabit.weekdays = weekdays
            targetHabit.periodTarget = max(1, periodTarget)
            targetHabit.reminderEnabled = reminderEnabled
            targetHabit.reminderHour = components.hour ?? 9
            targetHabit.reminderMinute = components.minute ?? 0
            targetHabit.startDate = calendar.startOfDay(for: startDate)
            targetHabit.endDate = hasEndDate ? calendar.startOfDay(for: endDate) : nil
            targetHabit.archived = archived
            targetHabit.updatedAt = .now
            if isNew { targetHabit.position = store.habits.count }
        }
        guard success else { return }
        Feedback.success()
        store.reschedule()
        saved = true
        if reminderEnabled, store.notifications.authorization == .notDetermined {
            showPermissionExplainer = true
        } else {
            dismiss()
        }
    }
}

struct HabitDetailView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var showArchived = false

    private var stats: HabitStats { store.habitStats(habit) }
    private var accent: Color { Palette.color(habit.color) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        SymbolTile(symbol: habit.icon, color: accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(habit.name).font(.title2.weight(.bold))
                            Text(habit.frequencyDescription).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        HabitProgressRing(fraction: stats.completedToday ? 1 : min(1, stats.todayValue / max(0.0001, stats.todayTarget)), size: 64, color: accent)
                    }
                    if !habit.details.isEmpty { Text(habit.details).font(.subheadline).foregroundStyle(.secondary) }

                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stats.completedToday ? "Done for today" : "Today’s intention").font(.headline)
                                    Text(kindDescription).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    store.toggleHabit(habit)
                                } label: {
                                    Image(systemName: stats.completedToday ? "checkmark.circle.fill" : "circle")
                                        .font(.title).foregroundStyle(stats.completedToday ? Palette.color("mint") : accent)
                                        .frame(width: 48, height: 48)
                                }.buttonStyle(PressStyle())
                                    .accessibilityLabel(stats.completedToday ? "Mark incomplete" : "Complete habit")
                            }
                            if habit.kind != .checkmark {
                                HStack(spacing: 12) {
                                    Button { store.setHabitProgress(habit, on: .now, value: max(0, stats.todayValue - habit.step)) } label: {
                                        Image(systemName: "minus").frame(width: 44, height: 44).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).disabled(stats.todayValue <= 0)
                                    Text("\(stats.todayValue.compact) / \(stats.todayTarget.compact) \(habit.unit)")
                                        .font(.title3.weight(.semibold)).monospacedDigit().frame(maxWidth: .infinity)
                                    Button { store.incrementHabit(habit) } label: {
                                        Image(systemName: "plus").frame(width: 44, height: 44).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        HabitStatCard(value: "\(stats.currentStreak)", label: "Current streak", icon: "flame.fill", color: "amber")
                        HabitStatCard(value: "\(stats.longestStreak)", label: "Longest streak", icon: "crown.fill", color: "lavender")
                        HabitStatCard(value: "\(Int((stats.completionRate * 100).rounded()))%", label: "Completion", icon: "chart.line.uptrend.xyaxis", color: "mint")
                        HabitStatCard(value: "\(stats.totalCompletions)", label: "Check-ins", icon: "checkmark.circle", color: "blue")
                    }

                    SectionHeading(title: "Your month", subtitle: "Tap a past day to adjust it.")
                    HabitMonthCalendar(habit: habit)

                    SectionHeading(title: "This week", subtitle: stats.periodLabel)
                    ProgressView(value: Double(stats.periodProgress), total: Double(max(1, stats.periodTarget))).tint(accent)
                    Text("\(stats.periodProgress) of \(stats.periodTarget) complete").font(.caption).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.pageBackground()
                .navigationTitle(habit.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(habit.archived ? "Unarchive" : "Archive", systemImage: "archivebox") { store.setHabitArchived(habit, archived: !habit.archived) }
                            Button("Delete habit", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
                .sheet(isPresented: $editing) { HabitEditor(habit: habit) }
                .confirmationDialog("Delete this habit and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete habit", role: .destructive) { store.deleteHabit(habit); dismiss() }
                } message: { Text("This permanently removes every check-in for \(habit.name).") }
        }
    }

    private var kindDescription: String {
        if habit.frequency == .weekly || habit.frequency == .monthly {
            return "\(stats.periodProgress) of \(stats.periodTarget) \(habit.frequency == .weekly ? "this week" : "this month")"
        }
        return habit.kind == .checkmark ? "One check-in is enough." : "\(stats.todayValue.compact) of \(stats.todayTarget.compact) \(habit.unit)"
    }
}

private struct HabitStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Palette.color(color))
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HabitMonthCalendar: View {
    @Environment(DaymarkStore.self) private var store
    let habit: Habit
    @State private var anchor = Date()
    private var calendar: Calendar { .current }
    private var month: DateInterval { calendar.dateInterval(of: .month, for: anchor)! }
    private var accent: Color { Palette.color(habit.color) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(anchor.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(month.end > Date())
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<gridSlots, id: \.self) { index in
                    if index < leading || index >= leading + dayCount { Color.clear.frame(height: 36) }
                    else {
                        let date = calendar.date(byAdding: .day, value: index - leading, to: month.start)!
                        dayButton(date)
                    }
                }
            }
        }
    }

    private var leading: Int { (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7 }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: anchor)!.count }
    private var gridSlots: Int { ((leading + dayCount + 6) / 7) * 7 }

    private func dayButton(_ date: Date) -> some View {
        let scheduled = store.isHabitScheduled(habit, on: date)
        let complete = store.isHabitComplete(habit, on: date)
        let future = date > Date()
        let isToday = calendar.isDateInToday(date)
        return Button {
            guard !future, scheduled else { return }
            store.toggleHabit(habit, on: date)
        } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day())).font(.caption.weight(isToday ? .bold : .regular))
                Circle().fill(complete ? accent : scheduled ? accent.opacity(0.12) : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay { if complete { Image(systemName: "checkmark").font(.system(size: 5, weight: .bold)).foregroundStyle(.white) } }
            }.frame(maxWidth: .infinity, minHeight: 36)
                .background(isToday ? accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .opacity(future ? 0.35 : 1)
        }.buttonStyle(.plain).disabled(future || !scheduled)
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            .accessibilityValue(complete ? "Completed" : scheduled ? "Scheduled" : "Not scheduled")
    }

    private func move(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: anchor) else { return }
        if amount > 0 && month.end > Date() { return }
        anchor = next
    }
}

struct ArchivedHabitsView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                let archived = store.habits.filter(\.archived)
                if archived.isEmpty {
                    ContentUnavailableView("Nothing archived", systemImage: "archivebox", description: Text("Habits you archive will rest here without losing their history."))
                } else {
                    ForEach(archived) { habit in
                        HStack {
                            SymbolTile(symbol: habit.icon, color: Palette.color(habit.color))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(habit.name).font(.headline)
                                Text("\(store.habitCompletions(for: habit).filter(\.completed).count) check-ins").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unarchive") { store.setHabitArchived(habit, archived: false) }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }.navigationTitle("Archived habits").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
