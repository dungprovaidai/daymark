import SwiftUI
import SwiftData
import UserNotifications

@main struct DaymarkApp: App {
    private let notificationDelegate = NotificationDelegate()
    private let container: ModelContainer?
    private let startupError: String?
    @State private var store: DaymarkStore?
    @State private var lock = AppLockController()
    @AppStorage("appearance") private var appearance = "system"

    init() {
        do {
            let schema = Schema([Journal.self, JournalSection.self, CustomField.self, JournalEntry.self, FieldValue.self,
                                 CalendarEvent.self, Reminder.self, Recurrence.self, EventException.self, SavedTemplate.self,
                                 Habit.self, HabitCompletion.self])
            let configuration = ModelConfiguration("Daymark", schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container; startupError = nil
            _store = State(initialValue: DaymarkStore(context: container.mainContext))
        } catch {
            container = nil; startupError = error.localizedDescription
            _store = State(initialValue: nil)
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let container, let store {
                        RootView().environment(store).environment(AppRoute.shared).modelContainer(container)
                    } else {
                        ContentUnavailableView {
                            Label("Couldn’t open Daymark", systemImage: "externaldrive.badge.exclamationmark")
                        } description: {
                            Text("Your saved data has not been erased. Restart the app and try again.\n\n\(startupError ?? "Storage unavailable")")
                        }
                    }
                }
                if lock.isLocked {
                    AppLockView().environment(lock).transition(.opacity)
                }
            }
            .environment(lock)
            .tint(Palette.accent)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
    }
}

struct RootView: View {
    @Environment(DaymarkStore.self) private var store
    @Environment(AppRoute.self) private var route
    @Environment(AppLockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var route = route
        @Bindable var store = store
        TabView(selection: $route.selectedTab) {
            NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
            NavigationStack { CalendarView() }.tabItem { Label("Calendar", systemImage: "calendar") }.tag(1)
            NavigationStack { HabitsView() }.tabItem { Label("Habits", systemImage: "checkmark.circle") }.tag(2)
            NavigationStack { JournalView() }.tabItem { Label("Journal", systemImage: "book.closed") }.tag(3)
            NavigationStack { InsightsView() }.tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }.tag(4)
            NavigationStack { LibraryView() }.tabItem { Label("Library", systemImage: "books.vertical") }.tag(5)
        }
        .sheet(isPresented: $route.showSettings) {
            NavigationStack { SettingsView() }
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await activate() } }
            else if phase == .background {
                store.syncWidgetSnapshot()
                lock.lockIfNeeded()
            }
        }
        .onOpenURL { route.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.reschedule(); store.syncWidgetSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
            store.reschedule(); store.syncWidgetSnapshot()
        }
        .alert("Couldn’t save changes", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    @MainActor private func activate() async {
        store.applyPendingWidgetActions()
        await store.notifications.refreshPermission()
        store.reschedule()
        store.syncWidgetSnapshot()
    }
}
