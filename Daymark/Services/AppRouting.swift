import Foundation

extension AppRoute {
    /// Handles widget and notification deep links. Route values are observed by
    /// TodayView and CalendarView, which open the requested date or event.
    func handle(_ url: URL) {
        guard url.scheme == DaymarkShared.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        switch components.host?.lowercased() {
        case "today":
            selectedTab = 0
            journalID = items["journal"].flatMap(UUID.init(uuidString:))
            journalDate = items["date"].flatMap { SharedDayKey.date(from: $0) }
            focusedFieldID = items["field"].flatMap(UUID.init(uuidString:))
            navigationToken += 1
        case "event":
            selectedTab = 1
            if let timestamp = items["start"].flatMap(Double.init) {
                calendarDate = Date(timeIntervalSince1970: timestamp)
            }
            eventID = items["event"].flatMap(UUID.init(uuidString:))
            navigationToken += 1
        case "calendar":
            selectedTab = 1
            if let value = items["date"], let date = SharedDayKey.date(from: value) { calendarDate = date }
            navigationToken += 1
        case "habits":
            selectedTab = 2
            habitID = items["habit"].flatMap(UUID.init(uuidString:))
            navigationToken += 1
        case "journal":
            selectedTab = 3
            journalID = items["journal"].flatMap(UUID.init(uuidString:))
            journalDate = items["date"].flatMap { SharedDayKey.date(from: $0) }
            navigationToken += 1
        case "insights":
            selectedTab = 4
            navigationToken += 1
        case "library":
            selectedTab = 5
            navigationToken += 1
        case "settings":
            showSettings = true
            navigationToken += 1
        default:
            break
        }
    }

    func openEvent(_ eventID: UUID?, at date: Date?) {
        selectedTab = 1
        if let date { calendarDate = date }
        self.eventID = eventID
        navigationToken += 1
    }

    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        let eventID = (userInfo["eventID"] as? String).flatMap(UUID.init(uuidString:))
        let start = (userInfo["start"] as? Double).map(Date.init(timeIntervalSince1970:))
        if eventID != nil {
            openEvent(eventID, at: start)
        } else if let value = userInfo["deepLink"] as? String, let url = URL(string: value) {
            handle(url)
        } else {
            selectedTab = 0
            navigationToken += 1
        }
    }
}
