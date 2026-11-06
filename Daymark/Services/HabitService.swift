import Foundation
import SwiftData

extension DaymarkStore {
    var activeHabits: [Habit] {
        let today = Calendar.current.startOfDay(for: .now)
        return habits.filter { habit in
            guard !habit.archived, Calendar.current.startOfDay(for: habit.startDate) <= today else { return false }
            guard let end = habit.endDate else { return true }
            return Calendar.current.startOfDay(for: end) >= today
        }
    }

    func habit(withID id: UUID) -> Habit? {
        habits.first { $0.id == id }
    }

    func habitCompletion(_ habit: Habit, on date: Date) -> HabitCompletion? {
        let day = DayKey.string(date)
        return habitCompletions.first { $0.habitID == habit.id && $0.dayKey == day }
    }

    func habitCompletions(for habit: Habit) -> [HabitCompletion] {
        habitCompletions.filter { $0.habitID == habit.id }
    }

    func isHabitScheduled(_ habit: Habit, on date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard day >= calendar.startOfDay(for: habit.startDate) else { return false }
        if let end = habit.endDate, day > calendar.startOfDay(for: end) { return false }
        switch habit.frequency {
        case .daily, .weekly, .monthly:
            return true
        case .custom:
            return habit.weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    func isHabitComplete(_ habit: Habit, on date: Date) -> Bool {
        habitCompletion(habit, on: date)?.completed == true
    }

    func habitValue(_ habit: Habit, on date: Date) -> Double {
        habitCompletion(habit, on: date)?.value ?? 0
    }

    @discardableResult
    func setHabitProgress(_ habit: Habit, on date: Date, value: Double) -> Bool {
        let clamped = max(0, value)
        let target = habit.kind == .checkmark ? 1 : max(0.0001, habit.target)
        let complete = clamped >= target
        let saved = perform {
            let dayKey = DayKey.string(date)
            if let existing = self.habitCompletions.first(where: { $0.habitID == habit.id && $0.dayKey == dayKey }) {
                if clamped == 0 { context.delete(existing) }
                else {
                    existing.value = clamped
                    existing.completed = complete
                    existing.updatedAt = .now
                }
            } else if clamped > 0 {
                let completion = HabitCompletion(habitID: habit.id, date: date)
                completion.value = clamped
                completion.completed = complete
                context.insert(completion)
            }
        }
        if saved { Feedback.tap() }
        return saved
    }

    @discardableResult
    func toggleHabit(_ habit: Habit, on date: Date = .now) -> Bool {
        if isHabitComplete(habit, on: date) {
            return setHabitProgress(habit, on: date, value: 0)
        }
        let value = habit.kind == .checkmark ? 1 : max(habit.step, habit.target)
        return setHabitProgress(habit, on: date, value: value)
    }

    @discardableResult
    func incrementHabit(_ habit: Habit, on date: Date = .now, by amount: Double? = nil) -> Bool {
        let step = amount ?? max(0.01, habit.step)
        let current = habitValue(habit, on: date)
        return setHabitProgress(habit, on: date, value: current + step)
    }

    func habitStats(_ habit: Habit, now: Date = .now) -> HabitStats {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: habit.startDate)
        let end = min(today, calendar.startOfDay(for: habit.endDate ?? today))
        let completions = habitCompletions(for: habit)
        let byDay = Dictionary(uniqueKeysWithValues: completions.map { ($0.dayKey, $0) })
        var stats = HabitStats()
        stats.scheduledToday = isHabitScheduled(habit, on: today)
        stats.completedToday = isHabitComplete(habit, on: today)
        stats.todayValue = habitValue(habit, on: today)
        stats.todayTarget = habit.kind == .checkmark ? 1 : max(0.0001, habit.target)
        stats.totalCompletions = completions.filter(\.completed).count

        switch habit.frequency {
        case .weekly, .monthly:
            let component: Calendar.Component = habit.frequency == .weekly ? .weekOfYear : .month
            stats.periodLabel = habit.frequency == .weekly ? "This week" : "This month"
            stats.periodTarget = max(1, habit.periodTarget)
            let period = calendar.dateInterval(of: component, for: today) ?? DateInterval(start: today, duration: 1)
            stats.periodProgress = completions.filter { $0.completed && $0.date >= period.start && $0.date < period.end }.count
            stats.currentStreak = periodStreak(habit: habit, component: component, now: today, calendar: calendar)
            stats.longestStreak = longestPeriodStreak(habit: habit, component: component, now: today, calendar: calendar)
            let periods = periodCount(habit: habit, component: component, now: today, calendar: calendar)
            let completedPeriods = periods.filter { periodCompleted(habit: habit, interval: $0, calendar: calendar) }.count
            stats.completionRate = periods.isEmpty ? 0 : Double(completedPeriods) / Double(periods.count)
        case .daily, .custom:
            stats.periodLabel = "This week"
            stats.periodTarget = 7
            let week = calendar.dateInterval(of: .weekOfYear, for: today) ?? DateInterval(start: today, duration: 1)
            stats.periodProgress = completions.filter { $0.completed && $0.date >= week.start && $0.date < week.end }.count
            stats.currentStreak = dailyStreak(habit: habit, from: start, through: end, byDay: byDay, calendar: calendar)
            stats.longestStreak = longestDailyStreak(habit: habit, from: start, through: end, byDay: byDay, calendar: calendar)
            let scheduled = scheduledDays(habit: habit, from: start, through: end, calendar: calendar)
            let completed = scheduled.filter { byDay[DayKey.string($0)]?.completed == true }.count
            stats.completionRate = scheduled.isEmpty ? 0 : Double(completed) / Double(scheduled.count)
        }
        return stats
    }

    private func scheduledDays(habit: Habit, from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        guard end >= start else { return [] }
        var result: [Date] = []
        var day = start
        var guardCount = 0
        while day <= end, guardCount < 3_660 {
            if isHabitScheduled(habit, on: day) { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next; guardCount += 1
        }
        return result
    }

    private func dailyStreak(habit: Habit, from start: Date, through end: Date, byDay: [String: HabitCompletion], calendar: Calendar) -> Int {
        var day = end
        // Today being unfinished is a grace day, not a broken streak.
        if calendar.isDateInToday(day), isHabitScheduled(habit, on: day), byDay[DayKey.string(day)]?.completed != true {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = previous
        }
        var count = 0
        var guardCount = 0
        while day >= start, guardCount < 3_660 {
            if isHabitScheduled(habit, on: day) {
                guard byDay[DayKey.string(day)]?.completed == true else { break }
                count += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous; guardCount += 1
        }
        return count
    }

    private func longestDailyStreak(habit: Habit, from start: Date, through end: Date, byDay: [String: HabitCompletion], calendar: Calendar) -> Int {
        var best = 0, current = 0
        var day = start
        var guardCount = 0
        while day <= end, guardCount < 3_660 {
            if isHabitScheduled(habit, on: day) {
                if byDay[DayKey.string(day)]?.completed == true {
                    current += 1; best = max(best, current)
                } else { current = 0 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next; guardCount += 1
        }
        return best
    }

    private func periodCount(habit: Habit, component: Calendar.Component, now: Date, calendar: Calendar) -> [DateInterval] {
        let start = calendar.startOfDay(for: habit.startDate)
        var result: [DateInterval] = []
        var cursor = start
        var guardCount = 0
        while cursor <= now, guardCount < 600 {
            if let interval = calendar.dateInterval(of: component, for: cursor) {
                if result.last?.start != interval.start { result.append(interval) }
                cursor = interval.end
            } else { break }
            guardCount += 1
        }
        return result
    }

    private func periodCompleted(habit: Habit, interval: DateInterval, calendar: Calendar) -> Bool {
        let count = habitCompletions(for: habit).filter {
            $0.completed && $0.date >= interval.start && $0.date < interval.end
        }.count
        return count >= max(1, habit.periodTarget)
    }

    private func periodStreak(habit: Habit, component: Calendar.Component, now: Date, calendar: Calendar) -> Int {
        var cursor = now
        var count = 0
        var guardCount = 0
        while cursor >= calendar.startOfDay(for: habit.startDate), guardCount < 600 {
            guard let interval = calendar.dateInterval(of: component, for: cursor) else { break }
            if periodCompleted(habit: habit, interval: interval, calendar: calendar) {
                count += 1
            } else if interval.contains(now) {
                // The current week or month can still be completed.
            } else {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: interval.start) else { break }
            cursor = previous; guardCount += 1
        }
        return count
    }

    private func longestPeriodStreak(habit: Habit, component: Calendar.Component, now: Date, calendar: Calendar) -> Int {
        let periods = periodCount(habit: habit, component: component, now: now, calendar: calendar)
        var best = 0, current = 0
        for interval in periods {
            if periodCompleted(habit: habit, interval: interval, calendar: calendar) {
                current += 1; best = max(best, current)
            } else if !interval.contains(now) { current = 0 }
        }
        return best
    }

    /// Returns the number of completed check-ins in the current week (used on Today).
    func habitWeekProgress(_ habit: Habit, now: Date = .now) -> (done: Int, target: Int) {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 1)
        let done = habitCompletions(for: habit).filter { $0.completed && $0.date >= week.start && $0.date < week.end }.count
        return (done, habit.frequency == .weekly ? max(1, habit.periodTarget) : 7)
    }

    func deleteHabit(_ habit: Habit) {
        perform {
            habitCompletions.filter { $0.habitID == habit.id }.forEach { context.delete($0) }
            context.delete(habit)
        }
        reschedule()
    }

    func setHabitArchived(_ habit: Habit, archived: Bool) {
        perform {
            habit.archived = archived
            habit.updatedAt = .now
        }
        reschedule()
    }
}
