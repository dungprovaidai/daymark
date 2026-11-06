import SwiftUI
import Charts

enum InsightPeriod: String, CaseIterable {
    case day = "Day", week = "Week", month = "Month", year = "Year"
    var component: Calendar.Component {
        switch self { case .day: return .day; case .week: return .weekOfYear; case .month: return .month; case .year: return .year }
    }
}

struct InsightPoint: Identifiable {
    let fieldID: UUID
    let label: String
    let date: Date
    let value: Double
    var id: String { "\(fieldID)/\(date.timeIntervalSince1970)" }
}

struct InsightsView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(AppRoute.self) private var route
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period = InsightPeriod.week
    @State private var anchor = Date()
    @State private var primaryID: UUID?
    @State private var comparisonID: UUID?
    @State private var selectedDate: Date?
    private var range: DateInterval { Calendar.current.dateInterval(of: period.component, for: anchor)! }
    private var numericFields: [CustomField] { store.fields.filter { [.counter, .rating, .checkbox].contains($0.kind) } }
    private var primary: CustomField? { numericFields.first { $0.id == primaryID } ?? numericFields.first }
    private var comparable: [CustomField] {
        guard let primary else { return [] }
        return numericFields.filter { $0.id != primary.id && $0.kind == primary.kind && $0.unit == primary.unit && (primary.kind != .rating || $0.ratingMaximum == primary.ratingMaximum) }
    }
    private var chosen: [CustomField] {
        guard let primary else { return [] }
        return [primary] + comparable.filter { $0.id == comparisonID }
    }
    private var entries: [JournalEntry] { store.entries.filter { $0.date >= range.start && $0.date < range.end } }
    private var points: [InsightPoint] {
        let entryDates = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.date) })
        return chosen.flatMap { field -> [InsightPoint] in
            let values = store.values.filter { $0.fieldID == field.id && entryDates[$0.entryID] != nil }
            let grouped = Dictionary(grouping: values) { value in
                let date = entryDates[value.entryID]!
                return Calendar.current.dateInterval(of: period == .year ? .month : .day, for: date)!.start
            }
            return grouped.map { date, values in
                let total = values.reduce(0.0) { $0 + (field.kind == .checkbox ? ($1.checked ? 1 : 0) : $1.number) }
                return InsightPoint(fieldID: field.id, label: fieldLabel(field), date: date,
                                    value: field.kind == .rating ? total / Double(values.count) : total)
            }.sorted { $0.date < $1.date }
        }
    }
    private var currentStreak: Int {
        let days = Set(store.entries.map(\.dayKey))
        let cal = Calendar.current
        var date = cal.startOfDay(for: .now)
        if !days.contains(DayKey.string(date)) { date = cal.date(byAdding: .day, value: -1, to: date)! }
        var count = 0
        while days.contains(DayKey.string(date)) {
            count += 1; date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("See the small things add up.").font(.title2.weight(.bold))
                    Text("Patterns from the moments you’ve recorded.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)
                Picker("Time period", selection: $period) { ForEach(InsightPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous period")
                    Spacer()
                    Text(periodLabel).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next period")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    statistic("Recorded days", value: "\(Set(entries.map(\.dayKey)).count)", icon: "calendar", color: "lavender")
                    statistic("Current streak", value: "\(currentStreak) days", icon: "flame", color: "amber")
                }
                if !store.activeHabits.isEmpty {
                    SectionHeading(title: "Habits", subtitle: "How your small steps are adding up.")
                    Surface {
                        VStack(spacing: 14) {
                            ForEach(store.activeHabits) { habit in
                                let stats = store.habitStats(habit)
                                HStack(spacing: 12) {
                                    SymbolTile(symbol: habit.icon, color: Palette.color(habit.color))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(habit.name).font(.subheadline.weight(.medium))
                                        Text("\(stats.currentStreak) day streak · \(Int((stats.completionRate * 100).rounded()))% complete")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(stats.periodProgress)/\(stats.periodTarget)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.color(habit.color))
                                }
                            }
                        }
                    }
                }
                if let primary {
                    Surface {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                SymbolTile(symbol: primary.icon, color: Palette.color(primary.color))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your rhythm").font(.headline)
                                    Text(primary.kind == .rating ? "Average rating" : primary.kind == .checkbox ? "Completed check-ins" : "Recorded totals")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Picker("Field", selection: Binding(get: { primary.id }, set: { primaryID = $0; comparisonID = nil; selectedDate = nil })) {
                                ForEach(numericFields) { Text(fieldLabel($0)).tag($0.id) }
                            }.pickerStyle(.menu).padding(.horizontal, -12)
                            if points.isEmpty {
                                ContentUnavailableView("A little more time", systemImage: "chart.xyaxis.line", description: Text("Record this field in your journal to see its story here."))
                            } else {
                                if period == .day { dailyChart }
                                else { trendChart }
                                Text(period == .year ? "Monthly totals for counters and checkboxes; monthly averages for ratings. Missing records are excluded." : "Each point is a recorded day. Missing days are left unrecorded, not counted as zero.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !comparable.isEmpty {
                        Surface {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Compare a field").font(.headline)
                                Text("Fields with the same type and unit share a scale.").font(.caption).foregroundStyle(.secondary)
                                Picker("Compare", selection: $comparisonID) {
                                    Text("No comparison").tag(nil as UUID?)
                                    ForEach(comparable) { Text(fieldLabel($0)).tag(Optional($0.id)) }
                                }.pickerStyle(.menu).padding(.horizontal, -12)
                            }
                        }
                    }
                    if !points.isEmpty {
                        SectionHeading(title: "In this period")
                        ForEach(chosen) { field in
                            let entryIDs = Set(entries.map(\.id))
                            let values = store.values.filter { $0.fieldID == field.id && entryIDs.contains($0.entryID) }
                            let total = values.reduce(0.0) { $0 + (field.kind == .checkbox ? ($1.checked ? 1 : 0) : $1.number) }
                            let summary = field.kind == .rating && !values.isEmpty ? total / Double(values.count) : total
                            Surface {
                                HStack(spacing: 12) {
                                    SymbolTile(symbol: field.icon, color: Palette.color(field.color))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(fieldLabel(field)).font(.subheadline.weight(.medium))
                                        Text(field.kind == .rating ? "Average across recorded days" : "Total \(field.unit)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(summary.compact).font(.title2.weight(.semibold)).monospacedDigit()
                                }
                            }
                        }
                    }
                } else {
                    EmptyCard(symbol: "chart.bar.xaxis", title: "Your patterns will grow here", message: "Add a counter, rating, or checkbox in Library, then record a few days to begin.")
                    NavigationLink("Open Library") { LibraryView() }.buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.pageBackground().navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { route.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .onChange(of: period) { _, _ in selectedDate = nil }
    }
    private var dailyChart: some View {
        Chart(points) { point in
            BarMark(x: .value("Field", point.label), y: .value("Value", point.value))
                .foregroundStyle(by: .value("Field", point.label)).cornerRadius(6)
                .annotation(position: .top) { Text(point.value.compact).font(.caption.weight(.medium)) }
                .accessibilityLabel(point.label).accessibilityValue(point.value.compact)
        }.chartForegroundStyleScale(range: [Palette.accent, Palette.color("mint")]).chartLegend(.hidden).frame(height: 240)
    }
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedDate, let point = points.min(by: { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }) {
                Text("\(point.date.formatted(date: .abbreviated, time: .omitted)) · \(point.label): \(point.value.compact)")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            } else { Text("Touch the chart to explore").font(.caption).foregroundStyle(.secondary) }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(by: .value("Field", point.label)).symbol(by: .value("Field", point.label))
                        .interpolationMethod(.linear)
                        .accessibilityLabel("\(point.label), \(point.date.formatted(date: .abbreviated, time: .omitted))")
                        .accessibilityValue(point.value.compact)
                }
                if let selectedDate { RuleMark(x: .value("Selected date", selectedDate)).foregroundStyle(.secondary.opacity(0.35)).lineStyle(StrokeStyle(dash: [4])) }
            }
            .chartForegroundStyleScale(range: [Palette.accent, Palette.color("mint")])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXSelection(value: $selectedDate)
            .chartXScale(domain: range.start...range.end)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 250)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: period)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: comparisonID)
        }
    }
    private func statistic(_ title: String, value: String, icon: String, color: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                SymbolTile(symbol: icon, color: Palette.color(color))
                Text(value).font(.title2.weight(.bold))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var periodLabel: String {
        switch period {
        case .day: return anchor.formatted(date: .abbreviated, time: .omitted)
        case .week: return "\(range.start.formatted(.dateTime.month(.abbreviated).day())) – \(range.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month: return anchor.formatted(.dateTime.month(.wide).year())
        case .year: return anchor.formatted(.dateTime.year())
        }
    }
    private func fieldLabel(_ field: CustomField) -> String {
        let journal = store.journals.first { $0.id == field.journalID }?.title ?? "Journal"
        return "\(field.title) · \(journal)\(field.archived ? " (archived)" : "")"
    }
    private func move(_ amount: Int) { anchor = Calendar.current.date(byAdding: period.component, value: amount, to: anchor) ?? anchor; selectedDate = nil }
}
