import SwiftUI

struct LibraryView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(AppRoute.self) private var route
    @State private var addJournal = false
    @State private var editingJournal: Journal?
    @State private var deletingJournal: Journal?
    @State private var templates = false
    @State private var searchText = ""
    @State private var selectedMilestone: EventOccurrence?
    @State private var showMilestone = false

    private var visibleJournals: [Journal] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.journals }
        return store.journals.filter { $0.title.lowercased().contains(query) }
    }

    private var milestones: [EventOccurrence] {
        let end = Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now
        return store
            .occurrences(in: DateInterval(start: .now, end: end))
            .filter { $0.event.category == .celebration && !$0.completed && $0.start > .now }
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A place for what matters").font(.title2.weight(.bold))
                    Text("Shape your journals around your life.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            Section("Your journals") {
                ForEach(visibleJournals) { journal in
                    NavigationLink { JournalLibraryView(journal: journal) } label: {
                        HStack(spacing: 14) {
                            SymbolTile(symbol: journal.icon, color: Palette.color(journal.color))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(journal.title).font(.headline)
                                Text("\(store.activeFields(in: journal.id).count) fields · \(store.entries.filter { $0.journalID == journal.id }.count) entries")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                    .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { deletingJournal = journal } }
                    .swipeActions(edge: .leading) { Button("Edit") { editingJournal = journal }.tint(Palette.accent) }
                    .contextMenu {
                        Button("Edit journal", systemImage: "pencil") { editingJournal = journal }
                        Button("Save as template", systemImage: "square.on.square") { store.saveTemplate(from: journal); Feedback.success() }
                        Button("Delete journal", systemImage: "trash", role: .destructive) { deletingJournal = journal }
                    }
                }.onMove { source, destination in
                    var journals = store.journals; journals.move(fromOffsets: source, toOffset: destination)
                    store.perform { for (index, journal) in journals.enumerated() { journal.position = index } }
                }
                Button { addJournal = true } label: { Label("New journal", systemImage: "plus") }
            }
            Section {
                Button { templates = true } label: {
                    HStack(spacing: 14) {
                        SymbolTile(symbol: "square.grid.2x2", color: Palette.color("amber"))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A thoughtful starting point").font(.headline).foregroundStyle(.primary)
                            Text("Browse and manage templates").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 6)
                }
            } footer: { Text("Templates add configurable fields. They never create sample journal records.") }

            Section("Milestones") {
                if milestones.isEmpty {
                    Text("No milestones yet. Add a celebration to see it here with its countdown.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(milestones) { occurrence in
                        EventRow(occurrence: occurrence, showDate: true) { selectedMilestone = occurrence }
                    }
                }
                Button {
                    showMilestone = true
                } label: {
                    Label("Add a milestone", systemImage: "sparkles")
                }
            }

            Section("Archive") {
                NavigationLink {
                    ArchivedHabitsView()
                } label: {
                    Label("Archived habits", systemImage: "archivebox")
                }
            }
        }.searchable(text: $searchText, prompt: "Search journals")
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button { route.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
                ToolbarItem(placement: .topBarTrailing) { Button { addJournal = true } label: { Image(systemName: "plus") }.accessibilityLabel("New journal") }
            }
            .sheet(isPresented: $addJournal) { JournalEditor() }
            .sheet(item: $editingJournal) { JournalEditor(journal: $0) }
            .sheet(isPresented: $templates) { TemplatesView() }
            .sheet(item: $selectedMilestone) { EventDetailView(occurrence: $0) }
            .sheet(isPresented: $showMilestone) { EventEditor(date: .now, category: .celebration) }
            .confirmationDialog("Delete journal and its entries?", isPresented: Binding(get: { deletingJournal != nil }, set: { if !$0 { deletingJournal = nil } }), titleVisibility: .visible) {
                Button("Delete journal", role: .destructive) { if let journal = deletingJournal { store.deleteJournal(journal) }; deletingJournal = nil }
            } message: { Text("This permanently deletes its sections, fields, and recorded entries. Scheduled events are kept, with journal links removed.") }
    }
}

struct JournalLibraryView: View {
    @Environment(DaymarkStore.self) private var store
    let journal: Journal
    @State private var addField = false
    @State private var editingField: CustomField?
    @State private var showSection = false
    @State private var editingSection: JournalSection?
    @State private var deletingSection: JournalSection?
    @State private var showArchived = false
    @State private var showTemplates = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    SymbolTile(symbol: journal.icon, color: Palette.color(journal.color))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your journal, your way").font(.headline)
                        Text("Add fields, group them into sections, and drag to reorder.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            fieldsSection(title: "General", sectionID: nil)
            ForEach(store.sections.filter { $0.journalID == journal.id }) { section in
                fieldsSection(title: section.title, sectionID: section.id)
            }
            Section("Organize") {
                Button { addField = true } label: { Label("Add field", systemImage: "plus.circle") }
                Button { editingSection = nil; showSection = true } label: { Label("Add section", systemImage: "folder.badge.plus") }
                Button { showTemplates = true } label: { Label("Apply a template", systemImage: "square.grid.2x2") }
                Button { store.saveTemplate(from: journal); Feedback.success() } label: { Label("Save as template", systemImage: "square.on.square") }
                NavigationLink("Manage sections") { SectionManager(journal: journal) }
                NavigationLink("Archived fields") { ArchivedFieldsView(journal: journal) }
            }
        }.navigationTitle(journal.title)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            .sheet(isPresented: $addField) { FieldEditor(journal: journal) }
            .sheet(item: $editingField) { FieldEditor(journal: journal, field: $0) }
            .sheet(isPresented: $showSection) { SectionEditor(journal: journal, section: editingSection) }
            .sheet(isPresented: $showTemplates) { TemplatesView(targetJournal: journal) }
    }
    private func fieldsSection(title: String, sectionID: UUID?) -> some View {
        let fields = store.activeFields(in: journal.id).filter { $0.sectionID == sectionID }
        return Section(title) {
            if fields.isEmpty { Text("No fields yet").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(fields) { field in
                Button { editingField = field } label: {
                    HStack(spacing: 12) {
                        SymbolTile(symbol: field.icon, color: Palette.color(field.color))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.title).foregroundStyle(.primary)
                            Text(field.kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 3)
                }.swipeActions { Button("Archive", systemImage: "archivebox") { store.perform { field.archived = true } }.tint(.orange) }
            }.onMove { source, destination in
                var ordered = fields; ordered.move(fromOffsets: source, toOffset: destination)
                store.perform { for (index, field) in ordered.enumerated() { field.position = index } }
            }
        }
    }
}

struct JournalEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let journal: Journal?
    @State private var title: String
    @State private var icon: String
    @State private var color: String
    init(journal: Journal? = nil) {
        self.journal = journal; _title = State(initialValue: journal?.title ?? "")
        _icon = State(initialValue: journal?.icon ?? "book.closed"); _color = State(initialValue: journal?.color ?? "lavender")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Journal name", text: $title); ColorPickerRow(selection: $color) }
                Section("Icon") { IconPicker(selection: $icon) }
            }.navigationTitle(journal == nil ? "New journal" : "Edit journal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if store.perform({
                                let target = journal ?? Journal(title: title, position: store.journals.count)
                                if journal == nil { store.context.insert(target) }
                                target.title = title.trimmingCharacters(in: .whitespacesAndNewlines); target.icon = icon; target.color = color
                            }) { dismiss() }
                        }.bold().disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

struct FieldEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let journal: Journal
    let field: CustomField?
    @State private var title: String
    @State private var kind: FieldKind
    @State private var sectionID: UUID?
    @State private var color: String
    @State private var icon: String
    @State private var unit: String
    @State private var step: Double
    @State private var target: Double
    @State private var maximum: Int
    @State private var options: String
    init(journal: Journal, field: CustomField? = nil) {
        self.journal = journal; self.field = field
        _title = State(initialValue: field?.title ?? ""); _kind = State(initialValue: field?.kind ?? .counter)
        _sectionID = State(initialValue: field?.sectionID); _color = State(initialValue: field?.color ?? "lavender")
        _icon = State(initialValue: field?.icon ?? "number"); _unit = State(initialValue: field?.unit ?? "")
        _step = State(initialValue: field?.step ?? 1); _target = State(initialValue: field?.target ?? 0)
        _maximum = State(initialValue: field?.ratingMaximum ?? 5); _options = State(initialValue: field?.options.joined(separator: "\n") ?? "")
    }
    private var hasHistory: Bool { field.map { field in store.values.contains { $0.fieldID == field.id } } ?? false }
    private var choices: [String] {
        var seen = Set<String>()
        return options.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && step.isFinite && step > 0 && target.isFinite && target >= 0
            && (kind != .choice || !choices.isEmpty)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Field name", text: $title)
                    Picker("Type", selection: $kind) { ForEach(FieldKind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                        .disabled(hasHistory).onChange(of: kind) { _, kind in icon = kind.icon }
                    Picker("Section", selection: $sectionID) {
                        Text("General").tag(nil as UUID?)
                        ForEach(store.sections.filter { $0.journalID == journal.id }) { Text($0.title).tag(Optional($0.id)) }
                    }
                } footer: { if hasHistory { Text("The type is locked once a field has recorded values. Create a new field to use another type.") } }
                if kind == .counter {
                    Section("Counter") {
                        TextField("Unit, e.g. minutes", text: $unit)
                        LabeledContent("Increase by") { TextField("Step", value: $step, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        LabeledContent("Daily goal") { TextField("Goal", value: $target, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        Text("Set a goal of 0 to record without a target. Counters start at zero and cannot be negative.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if kind == .rating {
                    Section("Rating") { Stepper("\(maximum) stars", value: $maximum, in: 2...10).disabled(hasHistory) }
                }
                if kind == .choice {
                    Section { TextField("One option per line", text: $options, axis: .vertical).lineLimit(4...12) }
                    header: { Text("Options") } footer: { Text("Duplicate and empty options are removed. Previously recorded choices stay in your history.") }
                }
                Section("Appearance") { ColorPickerRow(selection: $color); IconPicker(selection: $icon) }
            }.navigationTitle(field == nil ? "New field" : "Edit field").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold().disabled(!valid) }
                }
        }
    }
    private func save() {
        if store.perform({
            let targetField = field ?? CustomField(journalID: journal.id, title: title, kind: kind, position: store.fields.count)
            if field == nil { store.context.insert(targetField) }
            targetField.title = title.trimmingCharacters(in: .whitespacesAndNewlines); targetField.kindRaw = kind.rawValue
            targetField.sectionID = sectionID; targetField.color = color; targetField.icon = icon; targetField.unit = unit
            targetField.step = step; targetField.target = target; targetField.ratingMaximum = maximum; targetField.options = choices
        }) { Feedback.success(); dismiss() }
    }
}

struct SectionEditor: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let journal: Journal
    let section: JournalSection?
    @State private var title: String
    init(journal: Journal, section: JournalSection? = nil) { self.journal = journal; self.section = section; _title = State(initialValue: section?.title ?? "") }
    var body: some View {
        NavigationStack {
            Form { TextField("Section name", text: $title) }.navigationTitle(section == nil ? "New section" : "Edit section").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if store.perform({
                                if let section { section.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
                                else { store.context.insert(JournalSection(journalID: journal.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), position: store.sections.count)) }
                            }) { dismiss() }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.presentationDetents([.medium])
    }
}

struct SectionManager: View {
    @Environment(DaymarkStore.self) private var store
    let journal: Journal
    @State private var editing: JournalSection?
    var body: some View {
        let sections = store.sections.filter { $0.journalID == journal.id }
        List {
            Section {
                ForEach(sections) { section in Button(section.title) { editing = section }.foregroundStyle(.primary) }
                    .onDelete { offsets in offsets.map { sections[$0] }.forEach { store.deleteSection($0) } }
                    .onMove { source, destination in
                        var ordered = sections; ordered.move(fromOffsets: source, toOffset: destination)
                        store.perform { for (index, section) in ordered.enumerated() { section.position = index } }
                    }
            } footer: { Text("Deleting a section moves its fields to General. Recorded values are kept.") }
        }.navigationTitle("Sections").toolbar { EditButton() }.sheet(item: $editing) { SectionEditor(journal: journal, section: $0) }
    }
}

struct ArchivedFieldsView: View {
    @Environment(DaymarkStore.self) private var store
    let journal: Journal
    @State private var deleting: CustomField?
    var body: some View {
        List {
            Section {
                ForEach(store.fields.filter { $0.journalID == journal.id && $0.archived }) { field in
                    HStack { Label(field.title, systemImage: field.icon); Spacer(); Button("Restore") { store.perform { field.archived = false } }.buttonStyle(.borderless) }
                        .swipeActions { Button("Delete", role: .destructive) { deleting = field } }
                }
            } footer: { Text("Archived fields and their values remain available in Insights and data exports. Swipe to permanently delete a field and its history.") }
        }.navigationTitle("Archived fields")
            .confirmationDialog("Permanently delete this field and all its values?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete field and history", role: .destructive) {
                    if let field = deleting { store.perform { store.values.filter { $0.fieldID == field.id }.forEach { store.context.delete($0) }; store.context.delete(field) } }
                    deleting = nil
                }
            }
    }
}

struct TemplatesView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var targetJournal: Journal? = nil
    @State private var selection: TemplateDefinition?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(targetJournal.map { "Add fields to \($0.title). Your existing fields and records stay in place." } ?? "Choose a starting point for a new journal. Every field is yours to change.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Made for everyday life") { ForEach(TemplateDefinition.builtIns) { templateRow($0) } }
                Section("Your templates") {
                    if store.templates.isEmpty { Text("Save a journal as a template from its menu.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(store.templates) { template in
                        if let definition = template.definition {
                            templateRow(definition).swipeActions { Button("Delete", role: .destructive) { store.perform { store.context.delete(template) } } }
                        }
                    }
                }
            }.navigationTitle("Templates").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $selection) { template in
                    NavigationStack {
                        List {
                            Section { Text(template.subtitle).foregroundStyle(.secondary) }
                            Section("Fields included") {
                                ForEach(template.fields) { field in
                                    HStack { SymbolTile(symbol: field.icon, color: Palette.color(field.color)); VStack(alignment: .leading) { Text(field.title); Text(field.kind.title).font(.caption).foregroundStyle(.secondary) } }
                                }
                            }
                            Section { Button(targetJournal == nil ? "Create journal from template" : "Add these fields") { if store.applyTemplate(template, to: targetJournal) { selection = nil; dismiss() } } }
                        }.navigationTitle(template.title).navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selection = nil } } }
                    }
                }
        }
    }
    private func templateRow(_ template: TemplateDefinition) -> some View {
        Button { selection = template } label: {
            HStack(spacing: 14) {
                SymbolTile(symbol: template.icon, color: Palette.color(template.color))
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title).font(.headline).foregroundStyle(.primary)
                    Text(template.subtitle).font(.caption).foregroundStyle(.secondary)
                }.multilineTextAlignment(.leading).padding(.vertical, 8)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
