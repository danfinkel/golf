import Foundation

/// What happened on one calendar day, for the month calendar.
public struct DayLog: Sendable, Equatable, Identifiable {
    public let day: Date
    public let swings: Int
    public let sessions: Int
    public let rounds: Int
    public var id: Date { day }
    public var isActive: Bool { sessions > 0 || rounds > 0 }
}

public enum HomeMetrics {
    /// Full swings across all sessions (putting excluded).
    public static func totalSwings(_ activities: [ActivitySample], from start: Date? = nil, to end: Date? = nil) -> Int {
        activities.reduce(0) { sum, activity in
            guard Metrics.isFullSwing(typename: activity.typename, kind: activity.kind),
                  let strokes = activity.strokeCount, strokes > 0 else { return sum }
            if let start, activity.date < start { return sum }
            if let end, activity.date >= end { return sum }
            return sum + strokes
        }
    }

    /// The local month containing `date`, as [start, end).
    public static func month(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: .month, for: date)
    }

    /// One entry per day of the month containing `date`, first day first.
    /// A session is any activity with shots; rounds are course scorecards.
    public static func monthLog(
        containing date: Date,
        activities: [ActivitySample],
        roundDates: [Date],
        calendar: Calendar = .current
    ) -> [DayLog] {
        guard let month = month(containing: date, calendar: calendar) else { return [] }
        var swings: [Date: Int] = [:]
        var sessions: [Date: Int] = [:]
        var rounds: [Date: Int] = [:]
        for activity in activities where month.contains(activity.date) && activity.date < month.end {
            guard let strokes = activity.strokeCount, strokes > 0 else { continue }
            let day = calendar.startOfDay(for: activity.date)
            sessions[day, default: 0] += 1
            if Metrics.isFullSwing(typename: activity.typename, kind: activity.kind) {
                swings[day, default: 0] += strokes
            }
        }
        for roundDate in roundDates where month.contains(roundDate) && roundDate < month.end {
            rounds[calendar.startOfDay(for: roundDate), default: 0] += 1
        }
        var result: [DayLog] = []
        var day = month.start
        while day < month.end {
            result.append(DayLog(day: day, swings: swings[day] ?? 0, sessions: sessions[day] ?? 0, rounds: rounds[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Consecutive days with any TrackMan activity, ending today or yesterday.
    public static func streak(activeDays: Set<Date>, today: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if !activeDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), activeDays.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while activeDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
