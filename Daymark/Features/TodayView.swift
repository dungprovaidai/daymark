import SwiftUI

struct TodayView: View {
    @AppStorage("displayName") private var name = ""
    @Environment(AppRoute.self) private var route
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date()
    private var displayedDate: Date { route.journalDate ?? today }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: today)
        return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }
    var body: some View {
        JournalDayView(
            date: displayedDate,
            header: name.isEmpty ? greeting : "\(greeting), \(name)",
            journalID: route.journalID,
            focusedFieldID: route.focusedFieldID,
            focusToken: route.navigationToken
        )
            .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !Calendar.current.isDate(displayedDate, inSameDayAs: .now) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today") {
                            route.journalID = nil; route.journalDate = nil; route.focusedFieldID = nil
                            route.navigationToken += 1
                            Feedback.tap()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { route.selectedTab = 4 } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Preferences")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in today = .now }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = .now } }
    }
}

struct JournalDayView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let date: Date
    var header: String = "A day to remember"
    var focusedFieldID: UUID?
    var focusToken: Int
    @State private var journalID: UUID?
    @State private var showField = false
    @State private var showNote = false
    @State private var showTemplates = false
    @State private var showEvent = false
    @State private var showJournal = false
    @State private var deleteEntry = false
    init(date: Date, header: String = "A day to remember", journalID: UUID? = nil, focusedFieldID: UUID? = nil, focusToken: Int = 0) {
        self.date = date; self.header = header; self.focusedFieldID = focusedFieldID; self.focusToken = focusToken
        _journalID = State(initialValue: journalID)
    }
    private var journal: Journal? { store.journals.first { $0.id == journalID } ?? store.journals.first }
    private var entry: JournalEntry? { journal.flatMap { store.entry(journalID: $0.id, date: date) } }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                        .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                    Text(header).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text("A little reflection. A little progress.").foregroundStyle(.secondary).font(.subheadline)
                }.padding(.top, 12)
                if let journal {
                    if store.journals.count > 1 {
                        Picker("Journal", selection: Binding(get: { journal.id }, set: { journalID = $0 })) {
                            ForEach(store.journals) { item in Label(item.title, systemImage: item.icon).tag(item.id) }
                        }.pickerStyle(.menu).padding(.horizontal, -12)
                    }
                    progressCard(journal)
                    let fields = store.activeFields(in: journal.id)
                    if fields.isEmpty {
                        EmptyCard(symbol: "leaf", title: "Make room for your day", message: "Choose what matters to you. Start with a template or create your first field.")
                        Button { showTemplates = true } label: { Label("Explore templates", systemImage: "square.grid.2x2").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        HStack {
                            SectionHeading(title: journal.title, subtitle: "Small moments, thoughtfully recorded")
                            Spacer()
                            Menu {
                                Button("Add field", systemImage: "plus") { showField = true }
                                Button("Write a note", systemImage: "square.and.pencil") { showNote = true }
                                if entry != nil { Button("Delete this day’s entry", systemImage: "trash", role: .destructive) { deleteEntry = true } }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Journal actions")
                        }
                        fieldSection(fields.filter { $0.sectionID == nil })
                        ForEach(store.sections.filter { $0.journalID == journal.id }) { section in
                            let sectionFields = fields.filter { $0.sectionID == section.id }
                            if !sectionFields.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(section.title).font(.headline).foregroundStyle(.secondary)
                                    fieldSection(sectionFields)
                                }
                            }
                        }
                    }
                    let archived = store.fields.filter { $0.journalID == journal.id && $0.archived && store.value(fieldID: $0.id, entryID: entry?.id) != nil }
                    if !archived.isEmpty {
                        SectionHeading(title: "From archived fields", subtitle: "Your previously recorded values")
                        fieldSection(archived)
                    }
                    Button { showNote = true } label: {
                        Surface {
                            HStack(alignment: .top, spacing: 14) {
                                SymbolTile(symbol: "pencil.line", color: Palette.color("amber"))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("A moment to reflect").font(.headline).foregroundStyle(.primary)
                                    Text(entry?.note.isEmpty == false ? entry!.note : "What would you like to remember?")
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }.buttonStyle(PressStyle())
                    Menu {
                        Button("Journal field", systemImage: "slider.horizontal.3") { showField = true }
                        Button("Reflection", systemImage: "square.and.pencil") { showNote = true }
                        Button("Scheduled event", systemImage: "calendar.badge.plus") { showEvent = true }
                    } label: {
                        Label("Add to your day", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    EmptyCard(symbol: "book.closed", title: "Your story starts here", message: "Create a journal to begin recording your days.")
                    Button("Create journal") { showJournal = true }.buttonStyle(.borderedProminent)
                }
                Text("Record today. See your journey.").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.bottom, 12)
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.pageBackground()
            .sheet(isPresented: $showField) { if let journal { FieldEditor(journal: journal) } }
            .sheet(isPresented: $showNote) { if let journal { ReflectionEditor(journal: journal, date: date, initial: entry?.note ?? "") } }
            .sheet(isPresented: $showTemplates) { TemplatesView(targetJournal: journal) }
            .sheet(isPresented: $showEvent) { EventEditor(date: date) }
            .sheet(isPresented: $showJournal) { JournalEditor() }
            .confirmationDialog("Delete this day’s journal entry?", isPresented: $deleteEntry, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) { if let entry { store.deleteEntry(entry) } }
            } message: { Text("This removes the recorded values and reflection for this journal on this date. Your field definitions stay available.") }
            .onAppear { scrollToFocused(proxy) }
            .onChange(of: focusToken) { _, _ in scrollToFocused(proxy) }
            .onChange(of: focusedFieldID) { _, _ in scrollToFocused(proxy) }
        }
    }

    private func scrollToFocused(_ proxy: ScrollViewProxy) {
        guard let focusedFieldID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(focusedFieldID, anchor: .center) }
        }
    }

    private func progressCard(_ journal: Journal) -> some View {
        let progress = store.progress(journalID: journal.id, date: date)
        let fraction = progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total)
        return Surface {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Palette.accent.opacity(0.10), lineWidth: 7)
                    Circle().trim(from: 0, to: fraction).stroke(Palette.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: fraction)
                    Text(fraction, format: .percent.precision(.fractionLength(0))).font(.title3.weight(.bold)).monospacedDigit()
                }.frame(width: 74, height: 74).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(progress.total > 0 && progress.done == progress.total ? "A day well recorded" : "Your daily rhythm").font(.headline)
                    Text(progress.total == 0 ? "One small step is a lovely start." : "\(progress.done) of \(progress.total) fields complete")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if progress.total > 0 { ProgressView(value: fraction).tint(Palette.accent).accessibilityHidden(true) }
                }
            }.padding(.vertical, 4).accessibilityElement(children: .combine)
                .accessibilityLabel("Daily progress, \(progress.done) of \(progress.total) fields complete")
        }
    }

    private func fieldSection(_ fields: [CustomField]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                FieldInputRow(field: field, date: date, value: store.value(fieldID: field.id, entryID: entry?.id))
                    .id(field.id)
                    .padding(16)
                if index < fields.count - 1 { Divider().padding(.leading, 70) }
            }
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct FieldInputRow: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let field: CustomField
    let date: Date
    let value: FieldValue?
    @State private var showText = false
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SymbolTile(symbol: field.icon, color: Palette.color(field.color))
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.title).font(.body.weight(.medium))
                    if field.kind == .counter && !field.unit.isEmpty { Text(field.unit).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                if field.kind == .checkbox {
                    Button {
                        store.record(field, on: date) { $0.checked = !(value?.checked ?? false) }; Feedback.tap()
                    } label: {
                        Image(systemName: value?.checked == true ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(value?.checked == true ? Palette.color("mint") : Color.secondary.opacity(0.5))
                            .frame(width: 44, height: 44)
                    }.buttonStyle(PressStyle()).accessibilityLabel(field.title)
                        .accessibilityValue(value?.checked == true ? "Completed" : "Not completed")
                }
            }
            switch field.kind {
            case .counter:
                HStack(spacing: 12) {
                    counterButton("minus", label: "Decrease \(field.title)", delta: -field.step)
                        .disabled((value?.number ?? 0) <= 0)
                    Text((value?.number ?? 0).compact).font(.title2.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText()).frame(maxWidth: .infinity)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: value?.number)
                        .accessibilityLabel("\(field.title): \((value?.number ?? 0).compact) \(field.unit)")
                    counterButton("plus", label: "Increase \(field.title)", delta: field.step)
                }
                if field.target > 0 {
                    ProgressView(value: min(1, max(0, (value?.number ?? 0) / field.target))) {
                        Text("Goal · \(field.target.compact) \(field.unit)").font(.caption).foregroundStyle(.secondary)
                    }.tint(Palette.color(field.color))
                }
            case .rating:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], alignment: .leading, spacing: 2) {
                    ForEach(1...max(1, field.ratingMaximum), id: \.self) { rating in
                        Button { store.record(field, on: date) { $0.number = Double(rating) }; Feedback.tap() } label: {
                            Image(systemName: Double(rating) <= (value?.number ?? 0) ? "star.fill" : "star")
                                .font(.title3).foregroundStyle(Palette.color("amber")).frame(minHeight: 44)
                        }.buttonStyle(PressStyle()).accessibilityLabel("\(field.title), \(rating) of \(field.ratingMaximum)")
                    }
                }
            case .choice:
                Menu {
                    ForEach(field.options, id: \.self) { option in
                        Button { store.record(field, on: date) { $0.text = option }; Feedback.tap() } label: {
                            if value?.text == option { Label(option, systemImage: "checkmark") } else { Text(option) }
                        }
                    }
                } label: {
                    HStack { Text(value?.text.isEmpty == false ? value!.text : "Choose an option"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                        .padding(12).background(Palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityLabel(field.title)
            case .text:
                Button { draft = value?.text ?? ""; showText = true } label: {
                    Text(value?.text.isEmpty == false ? value!.text : "Tap to write…").font(.subheadline)
                        .foregroundStyle(value?.text.isEmpty == false ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).multilineTextAlignment(.leading)
                }.buttonStyle(.plain).accessibilityLabel("Edit \(field.title)")
            case .checkbox: EmptyView()
            }
        }
        .contextMenu {
            if let value { Button("Clear recorded value", systemImage: "eraser", role: .destructive) { store.perform { store.context.delete(value) } } }
        }
        .sheet(isPresented: $showText) {
            NavigationStack {
                TextEditor(text: $draft).padding().navigationTitle(field.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showText = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { if store.record(field, on: date, update: { $0.text = draft }) { showText = false } }.bold()
                        }
                    }
            }.presentationDetents([.medium, .large])
        }
    }
    private func counterButton(_ icon: String, label: String, delta: Double) -> some View {
        Button { store.record(field, on: date) { $0.number = max(0, $0.number + delta) }; Feedback.tap() } label: {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 48, height: 44)
                .background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(PressStyle()).accessibilityLabel(label)
    }
}

struct ReflectionEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let journal: Journal
    let date: Date
    @State private var note: String
    init(journal: Journal, date: Date, initial: String) { self.journal = journal; self.date = date; _note = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(date.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $note).accessibilityLabel("Reflection")
            }.padding(20).navigationTitle("A moment to reflect").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.saveNote(journalID: journal.id, date: date, note: note) { dismiss() } }.bold() }
                }
        }
    }
}
