import SwiftUI

struct JournalView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(AppRoute.self) private var route
    @State private var addJournal = false
    @State private var searchText = ""
    @State private var selectedJournalID: UUID?
    @State private var editingJournal: Journal?
    @State private var openRouteEntry = false

    private var journals: [Journal] { store.journals }
    private var selectedJournal: Journal? {
        journals.first { $0.id == selectedJournalID } ?? journals.first
    }
    private var recentEntries: [JournalEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let entries = store.entries.sorted { $0.date > $1.date }
        guard !query.isEmpty else { return Array(entries.prefix(60)) }
        let matchingValueEntries = Set(store.values.filter { $0.text.lowercased().contains(query) }.map(\.entryID))
        return entries.filter { entry in
            entry.note.lowercased().contains(query) ||
            matchingValueEntries.contains(entry.id) ||
            (journals.first { $0.id == entry.journalID }?.title.lowercased().contains(query) ?? false)
        }.prefix(100).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your days, gathered.").font(.title2.weight(.bold))
                    Text("Reflect, revisit, and notice what you’ve recorded.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)

                if let selectedJournal {
                    NavigationLink {
                        JournalDayView(date: .now, header: "A moment for today", journalID: selectedJournal.id)
                            .navigationTitle(selectedJournal.title).navigationBarTitleDisplayMode(.inline)
                    } label: {
                        JournalTodayCard(journal: selectedJournal)
                    }.buttonStyle(PressStyle())
                    if journals.count > 1 {
                        Picker("Journal", selection: Binding(get: { selectedJournal.id }, set: { selectedJournalID = $0 })) {
                            ForEach(journals) { journal in Label(journal.title, systemImage: journal.icon).tag(journal.id) }
                        }.pickerStyle(.menu).padding(.horizontal, -12)
                    }
                } else {
                    EmptyCard(symbol: "book.closed", title: "Your story starts here", message: "Create a journal and make a little room for your days.")
                    Button { addJournal = true } label: { Label("Create a journal", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }

                if !journals.isEmpty {
                    HStack {
                        SectionHeading(title: "Your journals", subtitle: "Shape each one around a part of your life.")
                        Spacer()
                        Button { addJournal = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .accessibilityLabel("New journal")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(journals) { journal in
                                JournalShelfCard(journal: journal)
                                    .contextMenu {
                                        Button("Edit journal", systemImage: "pencil") { editingJournal = journal }
                                    }
                            }
                        }.padding(.horizontal, 2)
                    }
                }

                HStack {
                    SectionHeading(title: "Recent entries", subtitle: searchText.isEmpty ? "The moments you’ve kept" : "Matching your search")
                    Spacer()
                }
                if recentEntries.isEmpty {
                    Text(searchText.isEmpty ? "Your entries will appear here once you begin writing." : "No entries match “\(searchText)”.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(recentEntries) { entry in
                            NavigationLink {
                                JournalDayView(date: entry.date, journalID: entry.journalID)
                                    .navigationTitle(store.journals.first { $0.id == entry.journalID }?.title ?? "Journal")
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                JournalEntryRow(entry: entry)
                            }.buttonStyle(PressStyle())
                        }
                    }
                }
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.pageBackground().navigationTitle("Journal")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search entries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { route.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addJournal = true } label: { Image(systemName: "plus") }.accessibilityLabel("New journal")
                }
            }
            .sheet(isPresented: $addJournal) { JournalEditor() }
            .sheet(item: $editingJournal) { JournalEditor(journal: $0) }
            .navigationDestination(isPresented: $openRouteEntry) {
                JournalDayView(date: route.journalDate ?? .now, journalID: route.journalID)
                    .navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            }
            .onAppear {
                selectedJournalID = selectedJournalID ?? route.journalID
                handleRoute()
            }
            .onChange(of: route.navigationToken) { _, _ in handleRoute() }
            .onChange(of: openRouteEntry) { _, isOpen in
                if !isOpen { route.journalDate = nil; route.journalID = nil }
            }
    }

    private func handleRoute() {
        guard route.selectedTab == 3 else { return }
        guard route.journalDate != nil || route.journalID != nil else { return }
        openRouteEntry = true
    }
}

private struct JournalTodayCard: View {
    @Environment(DaymarkStore.self) private var store
    let journal: Journal
    private var progress: (done: Int, total: Int) { store.progress(journalID: journal.id, date: .now) }
    private var entry: JournalEntry? { store.entry(journalID: journal.id, date: .now) }
    private var fraction: Double { progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total) }
    var body: some View {
        Surface {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Palette.accent.opacity(0.12), lineWidth: 6)
                    Circle().trim(from: 0, to: fraction).stroke(Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(fraction, format: .percent.precision(.fractionLength(0))).font(.headline.weight(.bold)).monospacedDigit()
                }.frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Today · \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(entry?.note.isEmpty == false ? "Continue your reflection" : "Write a little of today").font(.headline).foregroundStyle(.primary)
                    Text(progress.total == 0 ? "Add a field to begin." : "\(progress.done) of \(progress.total) fields complete").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            }
        }
    }
}

private struct JournalShelfCard: View {
    @Environment(DaymarkStore.self) private var store
    let journal: Journal
    var body: some View {
        let fields = store.activeFields(in: journal.id).count
        let entries = store.entries.filter { $0.journalID == journal.id }.count
        NavigationLink {
            JournalDayView(date: .now, journalID: journal.id)
                .navigationTitle(journal.title).navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                SymbolTile(symbol: journal.icon, color: Palette.color(journal.color))
                Text(journal.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text("\(fields) fields · \(entries) entries").font(.caption).foregroundStyle(.secondary)
            }.frame(width: 156, alignment: .leading)
                .padding(16)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(PressStyle())
    }
}

private struct JournalEntryRow: View {
    @Environment(DaymarkStore.self) private var store
    let entry: JournalEntry
    private var journal: Journal? { store.journals.first { $0.id == entry.journalID } }
    private var valueCount: Int { store.values.filter { $0.entryID == entry.id }.count }
    var body: some View {
        Surface {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 3) {
                    Text(entry.date.formatted(.dateTime.day())).font(.title3.weight(.bold)).monospacedDigit()
                    Text(entry.date.formatted(.dateTime.month(.abbreviated))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }.frame(width: 42).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: journal?.icon ?? "book.closed").font(.caption).foregroundStyle(Palette.color(journal?.color ?? "lavender"))
                        Text(journal?.title ?? "Journal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if valueCount > 0 { Text("\(valueCount) recorded").font(.caption2).foregroundStyle(.tertiary) }
                    }
                    Text(entry.note.isEmpty ? "A day with \(valueCount) recorded field\(valueCount == 1 ? "" : "s")" : entry.note)
                        .font(.subheadline).foregroundStyle(entry.note.isEmpty ? .secondary : .primary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
