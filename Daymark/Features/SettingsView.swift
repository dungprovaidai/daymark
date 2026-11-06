import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DaymarkStore.self) private var store
    @AppStorage("displayName") private var name = ""
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("haptics") private var haptics = true
    @State private var document = ExportDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var showExporter = false
    @State private var exportError: String?
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(Palette.accent.opacity(0.10)).frame(width: 64, height: 64)
                        Image(systemName: "sun.horizon.fill").font(.system(size: 32)).symbolRenderingMode(.palette).foregroundStyle(Palette.color("amber"), Palette.accent)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Daymark").font(.title2.weight(.bold))
                        Text("Record today. See your journey.").font(.caption).foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")").font(.caption2).foregroundStyle(.tertiary)
                    }
                }.padding(.vertical, 12)
            }
            Section("Make it yours") {
                TextField("Your name (optional)", text: $name).textContentType(.givenName)
                Picker(selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                Toggle(isOn: $haptics) { Label("Haptic feedback", systemImage: "hand.tap") }
                NavigationLink { NotificationSettingsView() } label: {
                    LabeledContent {
                        Text(store.notifications.statusTitle).foregroundStyle(.secondary)
                    } label: { Label("Notifications", systemImage: "bell") }
                }
            }
            Section {
                Button { export(as: .json) } label: { Label("Export all data (JSON)", systemImage: "square.and.arrow.up") }
                Button { export(as: .commaSeparatedText) } label: { Label("Export journal records (CSV)", systemImage: "tablecells") }
                NavigationLink { PrivacyView() } label: { Label("Data & privacy", systemImage: "lock.shield") }
            } header: { Text("Your data") } footer: {
                Text("JSON includes journals, fields, entries, events, reminders, repeat rules, exceptions, and templates. CSV is for journal analysis in spreadsheets.")
            }
            Section {
                NavigationLink { AboutView() } label: { Label("About Daymark", systemImage: "info.circle") }
            }
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "heart").foregroundStyle(Palette.accent)
                    Text("A little more present, every day.").font(.subheadline.weight(.medium))
                    Text("Thank you for making room for yourself.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 16)
            }.listRowBackground(Palette.accent.opacity(0.05))
        }.navigationTitle("Settings")
            .task { await store.notifications.refreshPermission() }
            .fileExporter(isPresented: $showExporter, document: document, contentType: exportType,
                          defaultFilename: "Daymark-\(DayKey.string(.now))") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Export could not be completed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
    }
    private func export(as type: UTType) {
        do {
            document = ExportDocument(data: type == .json ? try DataExport.json(store: store) : DataExport.csv(store: store))
            exportType = type; showExporter = true
        } catch { exportError = error.localizedDescription }
    }
}

struct NotificationSettingsView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var testMessage: String?
    @State private var showTestMessage = false
    var body: some View {
        List {
            Section { NotificationPermissionView() }
            Section {
                LabeledContent("Authorization", value: store.notifications.statusTitle)
                Button("Send test notification") {
                    Task {
                        testMessage = await store.notifications.sendTestNotification() ?? "Test notification scheduled for 3 seconds from now."
                        showTestMessage = true
                    }
                }
                .disabled(!store.notifications.canDeliver)
                if !store.notifications.canDeliver {
                    Text("The test becomes available after you allow notifications.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Test") } footer: {
                Text("A test is a real local notification. If iOS is in Focus or silent mode, the banner or sound may be suppressed.")
            }
            Section("Schedule status") {
                LabeledContent("Queued reminders", value: "\(store.notifications.queuedCount)")
                if let date = store.notifications.lastScheduledDate { LabeledContent("Last queued alert", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if store.notifications.omittedCount > 0 {
                    Text("\(store.notifications.omittedCount) additional alerts are waiting for space. Open Daymark regularly to refresh the queue.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let error = store.notifications.lastError { Text(error).foregroundStyle(.red) }
                Button("Refresh reminder schedule") { store.reschedule() }
                Button("Open iOS notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
            Section("How reminders work") {
                Text("Daymark schedules real, on-device iOS notifications. It keeps the nearest 60 future alerts queued and searches up to two years ahead for repeating events. One-off events can be scheduled further ahead.")
                Text("The queue refreshes when you open Daymark, edit events, or the system reports a clock or time-zone change while the app is running. Alerts already queued can arrive while the app is closed. Future alerts beyond that queue need another app refresh.")
                Text("Daymark cannot guarantee indefinite reminders without being reopened. Background execution, Focus, silent mode, and notification delivery are controlled by iOS.")
            }.font(.subheadline).foregroundStyle(.secondary)
        }.navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .task { await store.notifications.refreshPermission() }
            .alert("Test notification", isPresented: $showTestMessage) { Button("OK") { } } message: { Text(testMessage ?? "") }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await store.notifications.refreshPermission() }
            }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On your device") {
                Label("No account required", systemImage: "person.crop.circle.badge.checkmark")
                Label("No analytics or advertising SDKs", systemImage: "hand.raised")
                Label("No cloud synchronization", systemImage: "externaldrive")
                Text("Journals and events are stored locally with SwiftData. Daymark doesn’t send them to a server. Device backups may include app data according to your iOS backup settings.")
            }
            Section("You’re in control") {
                Text("Exports contain your personal information. Choose where to save or share them. JSON is a complete data export; this version does not include an import interface.")
                Text("Archived fields retain their history. Permanently deleting a field or journal removes its associated records. Deleting a journal unlinks events without deleting those events.")
                Text("Event titles and locations can appear in lock-screen notifications. You can change notification previews in iOS Settings.")
            }
        }.navigationTitle("Data & privacy").navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Text("Daymark").font(.largeTitle.weight(.bold))
                Text("A calm place to record your days, notice your patterns, and make time for what matters.")
            }
            Section("A few helpful details") {
                Text("Daily progress counts checked boxes, written text, selected choices, and ratings. A counter with a goal completes when it reaches that goal; a counter without a goal completes once recorded, including an explicitly recorded zero.")
                Text("A streak counts consecutive dates with a saved journal entry across any journal. Today can be unfinished while yesterday’s streak remains active.")
                Text("Recurring schedules use the event’s time zone. During a spring-forward gap, a missing time advances to the next valid time; during a fall-back overlap, the first occurrence of that time is used. Monthly and yearly schedules skip nonexistent dates.")
            }
        }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}
