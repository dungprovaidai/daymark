# Daymark

> Personal journal, calendar, habits, insights, and life-management app for iPhone.

Daymark is a local-first iOS app with six tabs — Today, Calendar, Habits, Journal, Insights, and Library — plus a Settings sheet. It uses SwiftData, WidgetKit, and local notifications. Your data stays on this device; there is no account or cloud sync in this build.

## Setup

1. Open `Daymark.xcodeproj` in Xcode or run the included project-generation script.
2. In the `Daymark` target’s **Signing & Capabilities**, select your Team and enable the App Group `group.com.example.Daymark` for both `Daymark` and `DaymarkWidgets`.
3. Set the bundle IDs: app `com.example.Daymark`, widgets `com.example.Daymark.Widgets`.
4. Run on a device for widgets, notifications, and Face ID; the simulator can run the app but cannot fully verify permission prompts.
5. If you fork the project, replace `group.com.example.Daymark` in `Daymark/Daymark.entitlements`, `DaymarkWidgets/DaymarkWidgets.entitlements`, and `Shared/SharedConfig.swift` with your own group.

## Features

- **Today**: customizable dashboard with show/hide and reorder, quick statistics, and Quick Capture for journal entries, events, reminders, habits, reflections, and milestones.
- **Journal**: multiple journals, sections, dynamic custom fields, search, and safe preservation of historical entries when fields are archived.
- **Calendar**: events, recurrence, reminders, completion, countdowns, and anniversaries.
- **Habits**: custom habits with daily/weekly/monthly/selected-day schedules, check-ins, counters, durations, streaks, history, reminders, archive, and delete.
- **Insights**: charts and statistics from your real journal entries and habit check-ins.
- **Library**: journals, templates, milestones, archived records, and search/filter organization.
- **Widgets**: Today’s overview, upcoming events, next event/countdown, habit progress, and lock-screen progress. Interactive habit and checklist taps update the widget immediately and are applied by the app on next activation through queued actions.
- **Notifications**: local only. Daymark does not ask for permission at launch; the first reminder or Settings explains the request and asks only on your action. Handles granted, denied, provisional, rescheduling, cancellation, time zones, and DST.
- **Backup**: JSON export/import with validation and confirmation before replacing data, plus CSV export for journal records.
- **Daymark AI providers**: Settings → Daymark AI → Providers supports multiple user-configured endpoints. Choose OpenAI-compatible, Gemini-native, or custom adapter modes; enter Base URL and Model ID manually; store API keys in Keychain; test a real small chat request; fetch models when supported; assign providers/models independently for Chat, Mood Analysis, Insights, and other AI tasks; configure capabilities and fallback explicitly. Daymark works offline with no AI provider.
- **App lock**: optional Face ID/Touch ID/passcode unlock with LocalAuthentication. If device authentication is unavailable, the app stays unlocked rather than trapping you outside your data.
- **Accessibility**: iOS 17+, light/dark mode, Dynamic Type, VoiceOver labels, and reduced-motion support.

## Screen Time / FamilyControls

Screen Time is optional. FamilyControls requires an Apple-approved entitlement and distribution role; it is not enabled in this project. You can request access through Apple if you have a suitable role, then add the entitlement and a Screen Time module without changing the core journal, calendar, or habit data models.

## Project notes

Daymark is a native iOS journal and event planner built with SwiftUI, SwiftData, Swift Charts, and UserNotifications. Minimum deployment target: **iOS 17**. There are no third-party runtime packages, accounts, servers, or cloud synchronization.

This is the actual application source and an Xcode project, not a browser mockup. It starts with an empty journal. Optional templates add field definitions, never fabricated records or analytics.

## Open and run

1. Unzip this folder on a Mac with **Xcode 16 or later** and an iOS Simulator runtime installed.
2. Open `Daymark.xcodeproj`. Select the shared **Daymark** scheme.
3. Choose an iPhone simulator and press **Run**. No project generation or dependency installation is needed.
4. To run on your iPhone, select the **Daymark** target → **Signing & Capabilities**, choose your development team, and replace `com.example.Daymark` with your own unique bundle identifier. Let Xcode manage signing.
5. In the app, open **Library → Templates** or **Today → Add to your day → Journal field** to configure your journal. Create events from Calendar’s plus button.
6. Open **Settings → Notifications → Enable notifications** to show the native iOS permission dialog. Set a test event a few minutes ahead and add an “At event time” reminder.

### Capabilities and configuration

- Local notifications do **not** need the Push Notifications capability, APNs keys, a server, or a special permission-description key in Info.plist. Authorization is requested at runtime using `UNUserNotificationCenter`.
- SwiftData is configured explicitly with `cloudKitDatabase: .none`. Do not add CloudKit for this build.
- No Calendar/EventKit, location, contacts, photo, or tracking permissions are requested. Location is a plain text field. Daymark’s calendar is its own local event store, not the system Calendar database.
- The checked-in asset catalog contains an opaque 1024×1024 app icon and separate light/dark accent colors.
- `PrivacyInfo.xcprivacy` declares app-scoped UserDefaults usage (`CA92.1`), no tracking, and no collected data. Review your App Store privacy questionnaire if you extend the app.
- No background mode is enabled. The notification queue is refreshed in the foreground; this is intentional and disclosed in the app.

## Implemented screens

| Destination | Behavior |
|---|---|
| Today | Localized date, configurable greeting, actual completion progress, journal selection, grouped dynamic fields, animated counters, immediate checkboxes, ratings, choices, text, reflection editor, templates, and empty states. |
| Calendar | Month/week/day modes, date jump, previous/next navigation, colored event dots, distinct journal markers, selected-day agenda, journal links, and chronological upcoming events. |
| Insights | Day/week/month/year ranges, previous/next period, selectable Swift Charts, compatible-field comparison, recorded-day statistics, current streak, and insufficient-data states. |
| Library | Create/edit/reorder/delete journals; create/edit/reorder sections and fields; archive, restore, or permanently delete fields; browse/apply built-in templates; save and delete personal templates. |
| Settings | Name, system/light/dark appearance, haptics, notification permission and queue status, full JSON export, journal CSV export, privacy, and help. |

All field rendering and statistics are derived from persisted field definitions. The examples in the optional templates are not hardcoded controls in the journal screens. Field types with recorded history are locked to avoid reinterpreting existing data; archive and create a new field to change its type.

## Events and reminders

Events store title, description, notes, start/end, all-day status, time zone, location, category, independently customizable color/icon, completion, and an optional journal-entry link. Single-day and multi-day events share the same interval logic.

Reminders support event time; 5/15/30 minutes; 1/2/6 hours; 1 day; 1 week; and custom amounts from 0–365 in minutes/hours/days/weeks. Tap a reminder to edit; swipe to delete. Each stored reminder has a stable ID. A scheduled notification ID combines the event ID, original occurrence instant, and reminder ID. Editing, completing, or deleting an event triggers a serialized reconciliation so a stale async pass cannot overwrite a newer edit.

The permission explanation appears before the system prompt. Denial keeps reminder settings intact and presents a Settings link. Notification taps open Calendar at the relevant occurrence. Foreground alerts use the native banner/sound/list presentation.

### Recurrence rules

- Daily, weekly, monthly, and yearly with a custom interval of 1–99.
- Weekly rules can select any combination of weekdays; no selection means the anchor date’s weekday. Interval weeks use Monday as the week boundary, independently of Calendar’s localized display.
- Optional end date is inclusive in the event’s time zone.
- “This occurrence” creates an exception and, for edits, a detached replacement event. The original slot is excluded, so it is not duplicated.
- “Entire series” changes the master. Changing its dates, time zone, all-day status, or recurrence resets per-date overrides and detached replacements after an explicit confirmation. Title/notes/category-only edits preserve exceptions and their detached replacements.
- Completion of a recurring event affects only that occurrence from the calendar controls. The full-series editor can mark the master complete.
- Deleting a series deletes its exceptions, detached events, and reminder settings. Deleting a detached occurrence leaves the original slot excluded.

### Time and calendar semantics

- Timed recurrence preserves wall-clock time in the event’s stored time zone. Traveling does not silently change the event’s original zone.
- All-day events also use the selected event time zone. In the editor the last day is inclusive; in persistence the end is exclusive. When viewed from another zone, their absolute intervals may overlap a neighboring local date.
- Nonexistent monthly dates are skipped: a January 31 monthly event has no February occurrence. A February 29 yearly event next appears in a leap year.
- In a spring-forward gap, nonexistent wall time advances to the next valid time. In a fall-back overlap, the first matching time is used. If both endpoints collapse to one instant, the original positive elapsed duration is preserved.
- “1 day before” uses calendar-day arithmetic; “24 hours before” uses hour arithmetic. They can differ across DST.
- Journal day keys are stable Gregorian civil dates captured when recorded. Events and journal entries use separate models and separate calendar indicators.

### Honest notification limits

Daymark queues the **nearest 60 future alerts** (a conservative on-device budget), expanding recurrence through the next **two years of reminder fire dates**. One-off alerts may be further away. The queue refreshes on launch, foreground entry, event changes, and clock/time-zone changes received while the app is running. Already queued alerts can arrive with the app closed.

**Alerts beyond the queued window need the app to be opened again.** This version does not promise indefinitely replenished reminders while the app remains closed, and does not depend on unreliable background refresh. Settings shows the queued count, the last queued date, errors, and how many generated alerts did not fit. Focus, lock-screen settings, sound settings, and final delivery are controlled by iOS. Past reminders are never fired retroactively.

## Data and exports

The observable `DaymarkStore` is the view-model/service boundary. Views use editable value drafts instead of mutating persistent event or field models while a sheet is open. Mutations are explicitly saved, with rollback and a surfaced error on failure. Models reference one another using stable UUIDs; cascade/unlink behavior is explicit in the store. This new app has no previous on-device schema to migrate. Future schema changes should add a versioned SwiftData migration plan rather than deleting the store.

JSON includes identifiers and all journals, sections, field definitions, entries, values, events, reminders, recurrence rules, exceptions, personal templates, and appearance preferences. Dates are ISO 8601. JSON uses export schema version 1. This release exports data but has **no import/restore UI**. CSV contains journal records only and quotes values, preserves Unicode, and neutralizes formula-leading cells; raw text is retained in JSON.

The app makes no network requests. iOS device backups may include app data according to the owner’s backup settings.

## Source map

| File | Responsibility |
|---|---|
| `Daymark/DaymarkApp.swift` | App bootstrap, local persistent schema, five native tabs, appearance, lifecycle reconciliation, and storage-failure state. |
| `Daymark/Models/Models.swift` | Journal, section, field, entry/value, event, reminder, recurrence, and exception models. |
| `Daymark/Models/EventDraft.swift` | Event editing state, validation, and inclusive/exclusive all-day conversion. |
| `Daymark/Models/Templates.swift` | Template definitions, persisted personal templates, apply/save logic. |
| `Daymark/Services/DaymarkStore.swift` | Persistence operations, daily progress, occurrence presentation, exceptions, and deletion semantics. |
| `Daymark/Services/RecurrenceEngine.swift` | Date-range expansion, custom intervals, weekdays, leap dates, and DST policies. |
| `Daymark/Services/NotificationCoordinator.swift` | Reminder planning, stable identifiers, permission status, serialized scheduling, foreground presentation, and notification routing. |
| `Daymark/Services/DataExport.swift` | Complete JSON export and journal CSV export through a native file document. |
| `Daymark/Design/DesignSystem.swift` | Adaptive surfaces, colors, icon tiles, press feedback, haptics, and reusable configuration controls. |
| `Daymark/Features/TodayView.swift` | Today and historical journal editing, field inputs, progress, and reflections. |
| `Daymark/Features/CalendarView.swift` | Month/week/day navigation, indicators, agenda, upcoming list, details, and recurrence edit/delete scopes. |
| `Daymark/Features/EventEditor.swift` | Event form, reminder editor, recurrence controls, time-zone picker, and permission explanation. |
| `Daymark/Features/InsightsView.swift` | Data-driven Swift Charts, summaries, streaks, period filtering, and compatible-field comparisons. |
| `Daymark/Features/LibraryView.swift` | Journal/section/field CRUD, reordering, archives, and templates. |
| `Daymark/Features/SettingsView.swift` | Preferences, exports, notification diagnostics, privacy, and help. |

## Validation status

Created and structurally checked on Windows. **No native build, XCTest execution, simulator rendering, or device notification delivery has been performed here.** There is no claimed successful Xcode build. Any compiler or signing diagnostics from the first Mac build remain to be resolved; no specific native build error is known because the build tools were unavailable.

Completed checks:

- All Swift sources and tests are referenced by the Xcode project.
- All 10 persistent model types are registered in the schema.
- Project object identifiers/references, scheme XML, privacy XML, asset JSON, and 1024×1024 opaque app icon verified.
- Swift lexical delimiter checks, including string interpolation and comments, passed. These are not Swift type checking.
- Manual source review corrected series-reset comparison ordering, DST-collapsed event duration, linked-journal selection, and weighted rating summaries.

**20 XCTest cases** are included in `DaymarkTests` for recurrence intervals/weekday rules, multi-day overlap, exclusive boundaries, end dates, invalid dates, leap years, spring/fall DST, reminder arithmetic, entry/value reuse, persistence through a new context, cascade/unlink behavior, recurrence exceptions, whole-series deletion/reset, notification IDs/filtering, and exports. They are included, not reported as passing.

On a Mac, run **Product → Test** or:

```sh
bash scripts/test-on-mac.sh
```

Optionally select a specific installed simulator:

```sh
DAYMARK_DESTINATION='platform=iOS Simulator,name=iPhone 16' bash scripts/test-on-mac.sh
```

The helper writes its result bundle under `build/`. Move an existing `build/DaymarkTests.xcresult` aside before a second run, or run tests directly in Xcode.

### Before treating this as a production release

1. Build and run the XCTest suite with Xcode. Check both Debug and Release.
2. Visually test a small iPhone (including landscape), a large iPhone, and iPad. Test light/dark appearance, VoiceOver, the largest Dynamic Type settings, Increase Contrast, and Reduce Motion. Recheck calendar cells and chart legends at large sizes.
3. On a physical device, test notification approval, denial, Settings re-enablement, foreground/background delivery, notification taps, edits, completion, deletion, and more than 60 requested alerts.
4. Save records, terminate/relaunch the app, and verify persistence. Export JSON/CSV and inspect accented text, multiline notes, dates, and linked IDs.
5. Test time-zone changes and DST transitions; confirm your product’s desired all-day and repeat-exception policies match those described above.

## Development helpers

`node scripts/validate-project.mjs` performs cross-platform structural checks. `node scripts/generate-project.mjs` regenerates the checked-in project after adding files; it replaces project settings with its deterministic definitions, so update the generator if you customize them. The icon is included; `scripts/create-icon.ps1` is an optional Windows-only asset regeneration helper.

## Apple references

- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [Scheduling local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Swift Charts interactivity in iOS 17](https://developer.apple.com/videos/play/wwdc2023/10037/)
- [Required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
