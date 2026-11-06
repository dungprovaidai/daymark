import SwiftUI
import WidgetKit

@main
struct DaymarkWidgetBundle: WidgetBundle {
    var body: some Widget {
        DaymarkOverviewWidget()
        DaymarkAgendaWidget()
        DaymarkNextEventWidget()
        DaymarkLockScreenWidget()
    }
}

struct DaymarkOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: DaymarkShared.kindOverview,
            intent: DaymarkWidgetConfigurationIntent.self,
            provider: DaymarkTimelineProvider(kind: DaymarkShared.kindOverview)
        ) { entry in
            DaymarkWidgetView(entry: entry, style: .overview)
        }
        .configurationDisplayName("Today’s overview")
        .description("Today’s date, journal progress, checklist, and what’s next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DaymarkAgendaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: DaymarkShared.kindAgenda,
            intent: DaymarkWidgetConfigurationIntent.self,
            provider: DaymarkTimelineProvider(kind: DaymarkShared.kindAgenda)
        ) { entry in
            DaymarkWidgetView(entry: entry, style: .agenda)
        }
        .configurationDisplayName("Upcoming agenda")
        .description("Your next events and reminders in one calm list.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DaymarkNextEventWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: DaymarkShared.kindNextEvent,
            intent: DaymarkWidgetConfigurationIntent.self,
            provider: DaymarkTimelineProvider(kind: DaymarkShared.kindNextEvent)
        ) { entry in
            DaymarkWidgetView(entry: entry, style: .nextEvent)
        }
        .configurationDisplayName("Next event")
        .description("The next thing on your calendar, plus journal progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DaymarkLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: DaymarkShared.kindLockScreen,
            provider: DaymarkLockScreenProvider()
        ) { entry in
            DaymarkLockScreenView(entry: entry)
        }
        .configurationDisplayName("Daymark progress")
        .description("A quiet glance at today’s journal progress and next event.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
