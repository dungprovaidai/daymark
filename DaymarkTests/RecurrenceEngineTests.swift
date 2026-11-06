import XCTest
@testable import Daymark

final class RecurrenceEngineTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func schedule(_ start: String, _ end: String, rule: RecurrenceRule? = nil, zone: String = "UTC", allDay: Bool = false) -> EventSchedule {
        .init(start: date(start), end: date(end), allDay: allDay, timeZoneID: zone, rule: rule)
    }
    private func times(_ schedule: EventSchedule, _ from: String, _ through: String) -> [OccurrenceTime] {
        RecurrenceEngine.occurrences(schedule, in: .init(start: date(from), end: date(through)))
    }
    func testSingleMultiDayEventAppearsOnEachOverlappingDay() {
        let event = schedule("2026-11-06T09:00:00Z", "2026-11-08T10:00:00Z")
        XCTAssertEqual(times(event, "2026-11-07T00:00:00Z", "2026-11-08T00:00:00Z").count, 1)
        XCTAssertTrue(times(event, "2026-11-08T10:00:00Z", "2026-11-09T00:00:00Z").isEmpty)
    }
    func testDailyCustomIntervalAndInclusiveUntilDate() {
        let rule = RecurrenceRule(frequency: .daily, interval: 2, until: date("2026-11-10T00:00:00Z"))
        let event = schedule("2026-11-06T09:00:00Z", "2026-11-06T10:00:00Z", rule: rule)
        let result = times(event, "2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z")
        XCTAssertEqual(result.map(\.start), [date("2026-11-06T09:00:00Z"), date("2026-11-08T09:00:00Z"), date("2026-11-10T09:00:00Z")])
    }
    func testBiweeklySelectedWeekdaysAndNoOccurrenceBeforeAnchor() {
        let event = schedule("2026-11-04T09:00:00Z", "2026-11-04T10:00:00Z", rule: .init(frequency: .weekly, interval: 2, weekdays: [2, 4]))
        let result = times(event, "2026-11-01T00:00:00Z", "2026-11-20T00:00:00Z")
        XCTAssertEqual(result.map(\.start), [date("2026-11-04T09:00:00Z"), date("2026-11-16T09:00:00Z"), date("2026-11-18T09:00:00Z")])
    }
    func testMonthlySkipsInvalidDayRatherThanClamping() {
        let event = schedule("2026-01-31T09:00:00Z", "2026-01-31T10:00:00Z", rule: .init(frequency: .monthly))
        XCTAssertEqual(times(event, "2026-01-01T00:00:00Z", "2026-04-01T00:00:00Z").map(\.start), [date("2026-01-31T09:00:00Z"), date("2026-03-31T09:00:00Z")])
    }
    func testLeapDayYearlySchedule() {
        let event = schedule("2024-02-29T09:00:00Z", "2024-02-29T10:00:00Z", rule: .init(frequency: .yearly))
        let result = times(event, "2025-01-01T00:00:00Z", "2029-01-01T00:00:00Z")
        XCTAssertEqual(result.map(\.start), [date("2028-02-29T09:00:00Z")])
    }
    func testSpringDSTKeepsNineAMLocalTime() {
        let event = schedule("2026-03-07T14:00:00Z", "2026-03-07T15:00:00Z", rule: .init(frequency: .daily), zone: "America/New_York")
        let result = times(event, "2026-03-07T00:00:00Z", "2026-03-10T00:00:00Z")
        XCTAssertEqual(result.map(\.start), [date("2026-03-07T14:00:00Z"), date("2026-03-08T13:00:00Z"), date("2026-03-09T13:00:00Z")])
    }
    func testMissingSpringTimeMovesToNextValidTime() {
        let event = schedule("2026-03-07T07:30:00Z", "2026-03-07T08:30:00Z", rule: .init(frequency: .daily), zone: "America/New_York")
        let result = times(event, "2026-03-08T00:00:00Z", "2026-03-09T00:00:00Z")
        XCTAssertEqual(result.first?.start, date("2026-03-08T07:00:00Z"))
        XCTAssertEqual(result.first?.end, date("2026-03-08T07:30:00Z"))
    }
    func testFallOverlapUsesFirstLocalTime() {
        let event = schedule("2026-10-31T05:30:00Z", "2026-10-31T06:30:00Z", rule: .init(frequency: .daily), zone: "America/New_York")
        let result = times(event, "2026-11-01T00:00:00Z", "2026-11-02T00:00:00Z")
        XCTAssertEqual(result.first?.start, date("2026-11-01T05:30:00Z"))
        XCTAssertEqual(result.first?.end, date("2026-11-01T07:30:00Z"))
    }
    func testAllDayDSTUsesCalendarDays() {
        let event = schedule("2026-03-07T05:00:00Z", "2026-03-08T05:00:00Z", rule: .init(frequency: .daily), zone: "America/New_York", allDay: true)
        let result = times(event, "2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].end.timeIntervalSince(result[0].start), 23 * 3600)
    }
    func testLongRecurringEventOverlapsRangeFromEarlierStart() {
        let event = schedule("2026-11-01T09:00:00Z", "2026-11-04T10:00:00Z", rule: .init(frequency: .weekly))
        XCTAssertEqual(times(event, "2026-11-03T00:00:00Z", "2026-11-04T00:00:00Z").first?.start, date("2026-11-01T09:00:00Z"))
    }
    func testReminderDayVersusHoursAcrossDST() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date("2026-03-08T13:00:00Z")
        XCTAssertEqual(ReminderSpec(amount: 1, unit: .days).fireDate(before: start, calendar: calendar), date("2026-03-07T14:00:00Z"))
        XCTAssertEqual(ReminderSpec(amount: 24, unit: .hours).fireDate(before: start, calendar: calendar), date("2026-03-07T13:00:00Z"))
    }
    func testInvalidDurationProducesNoOccurrence() {
        let event = schedule("2026-11-06T10:00:00Z", "2026-11-06T09:00:00Z", rule: .init(frequency: .daily))
        XCTAssertTrue(times(event, "2026-11-01T00:00:00Z", "2026-12-01T00:00:00Z").isEmpty)
    }
}
