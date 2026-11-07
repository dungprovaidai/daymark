import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Identifiers and files shared by the app and the WidgetKit extension.
///
/// Replace `appGroupIdentifier` and the bundle identifiers together with your
/// own Apple Developer team values before installing on a device.
enum DaymarkShared {
    static let appGroupIdentifier = "group.com.example.Daymark"
    static let urlScheme = "daymark"

    static let snapshotFileName = "WidgetSnapshot.json"
    static let actionsFileName = "WidgetActions.json"
    static let habitActionsFileName = "WidgetHabitActions.json"
    static let lockFileName = "WidgetShared.lock"
    static let fallbackDirectoryName = "DaymarkWidgetShared"

    static let kindOverview = "DaymarkOverviewWidget"
    static let kindAgenda = "DaymarkAgendaWidget"
    static let kindNextEvent = "DaymarkNextEventWidget"
    static let kindHabits = "DaymarkHabitsWidget"
    static let kindLockScreen = "DaymarkLockScreenWidget"

    static var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// The app group container when entitlements are available, otherwise a
    /// local fallback so development builds still run. The fallback is not
    /// shared with the widget extension.
    static var directoryURL: URL {
        if let appGroupURL { return appGroupURL }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fallbackDirectoryName, isDirectory: true)
    }

    static var snapshotURL: URL { directoryURL.appendingPathComponent(snapshotFileName) }
    static var actionsURL: URL { directoryURL.appendingPathComponent(actionsFileName) }
    static var habitActionsURL: URL { directoryURL.appendingPathComponent(habitActionsFileName) }
    static var lockURL: URL { directoryURL.appendingPathComponent(lockFileName) }

    static var isAppGroupAvailable: Bool { appGroupURL != nil }

    /// Short diagnostic summary for Settings → Widgets.
    static func diagnosticSummary() -> String {
        if let url = appGroupURL {
            return "App Group available: \(url.lastPathComponent)"
        }
        return "App Group unavailable — using local fallback (\(fallbackDirectoryName)). Widgets cannot read this data."
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

/// A small cross-process lock. The app group is the only place the app and the
/// widget share mutable files, and every read/write goes through this lock.
enum WidgetFileLock {
    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        DaymarkShared.ensureDirectory()
        #if canImport(Darwin)
        let descriptor = open(DaymarkShared.lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return try body() }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        _ = flock(descriptor, LOCK_EX)
        return try body()
        #else
        return try body()
        #endif
    }
}

enum SharedDayKey {
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return gregorian.date(from: components)
    }
}
