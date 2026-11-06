import Foundation

/// URL routes used by widgets and notification taps.
///
/// `daymark://today?journal=<uuid>&date=yyyy-MM-dd&field=<uuid>`
/// `daymark://event?event=<uuid>&start=<unix-seconds>`
/// `daymark://calendar?date=yyyy-MM-dd`
/// `daymark://settings`
enum DaymarkDeepLink {
    static func today(journalID: UUID? = nil, date: Date = .now, fieldID: UUID? = nil) -> URL {
        var components = URLComponents()
        components.scheme = DaymarkShared.urlScheme
        components.host = "today"
        var items = [URLQueryItem(name: "date", value: SharedDayKey.string(date))]
        if let journalID { items.append(URLQueryItem(name: "journal", value: journalID.uuidString)) }
        if let fieldID { items.append(URLQueryItem(name: "field", value: fieldID.uuidString)) }
        components.queryItems = items
        return components.url ?? URL(string: "daymark://today")!
    }

    static func event(eventID: UUID, start: Date) -> URL {
        var components = URLComponents()
        components.scheme = DaymarkShared.urlScheme
        components.host = "event"
        components.queryItems = [
            URLQueryItem(name: "event", value: eventID.uuidString),
            URLQueryItem(name: "start", value: String(start.timeIntervalSince1970))
        ]
        return components.url ?? URL(string: "daymark://event")!
    }

    static func calendar(date: Date) -> URL {
        var components = URLComponents()
        components.scheme = DaymarkShared.urlScheme
        components.host = "calendar"
        components.queryItems = [URLQueryItem(name: "date", value: SharedDayKey.string(date))]
        return components.url ?? URL(string: "daymark://calendar")!
    }

    static var settings: URL {
        URL(string: "daymark://settings")!
    }
}

extension WidgetEventInfo {
    var deepLink: URL { DaymarkDeepLink.event(eventID: eventID, start: start) }
}
