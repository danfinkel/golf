import Foundation

public enum Units {
    public static let yardsPerMeter = 1.0936132983
    public static let mphPerMetersPerSecond = 2.2369362921

    public static func yards(fromMeters meters: Double) -> Double { meters * yardsPerMeter }
}

/// Plain inputs so metrics are independent of the API and the database.
public struct RoundSample: Sendable, Equatable {
    public let id: String
    public let date: Date
    public let driveAverageMeters: Double?

    public init(id: String, date: Date, driveAverageMeters: Double?) {
        self.id = id
        self.date = date
        self.driveAverageMeters = driveAverageMeters
    }
}

public struct ActivitySample: Sendable, Equatable {
    public let id: String
    public let typename: String
    public let kind: String?
    public let date: Date
    public let strokeCount: Int?

    public init(id: String, typename: String, kind: String?, date: Date, strokeCount: Int?) {
        self.id = id
        self.typename = typename
        self.kind = kind
        self.date = date
        self.strokeCount = strokeCount
    }
}

public struct DrivePoint: Sendable, Equatable, Identifiable {
    public let id: String
    public let date: Date
    public let yards: Double
    /// Mean of this round and the previous four, or nil for the first four rounds.
    public let rollingYards: Double?
}

public struct DailySwings: Sendable, Equatable, Identifiable {
    public let day: Date
    public let count: Int
    public let byKind: [String: Int]
    public var id: Date { day }
}

public enum Metrics {
    public static let rollingWindow = 5

    /// Drive average per round, oldest first, with a rolling mean over the
    /// last `window` rounds. Rounds without a drive average are skipped.
    /// (Sorting before averaging fixes the notebook, which rolled over the
    /// newest-first CSV.)
    public static func driveTrend(_ rounds: [RoundSample], window: Int = rollingWindow) -> [DrivePoint] {
        let usable = rounds
            .compactMap { round -> (RoundSample, Double)? in
                guard let meters = round.driveAverageMeters, meters > 0 else { return nil }
                return (round, Units.yards(fromMeters: meters))
            }
            .sorted { $0.0.date < $1.0.date }

        let yards = usable.map(\.1)
        return usable.enumerated().map { index, entry in
            var rolling: Double?
            if window > 0, index + 1 >= window {
                let slice = yards[(index + 1 - window)...index]
                rolling = slice.reduce(0, +) / Double(window)
            }
            return DrivePoint(id: entry.0.id, date: entry.0.date, yards: entry.1, rollingYards: rolling)
        }
    }

    /// Headline for the drive card: the latest rolling average, or the plain
    /// mean when there are fewer rounds than the window.
    public static func headlineDrive(_ points: [DrivePoint]) -> Double? {
        if let latest = points.last?.rollingYards { return latest }
        guard !points.isEmpty else { return nil }
        return points.map(\.yards).reduce(0, +) / Double(points.count)
    }

    /// Full swings only: putting sessions are excluded.
    public static func isFullSwing(typename: String, kind: String?) -> Bool {
        let putting = typename.range(of: "putting", options: .caseInsensitive) != nil
            || (kind ?? "").range(of: "putt", options: .caseInsensitive) != nil
        return !putting
    }

    /// Swings per local calendar day for the `days` days ending on `now`'s day,
    /// oldest first, with zero-count days included.
    public static func dailySwings(_ activities: [ActivitySample], endingAt now: Date, days: Int = 30, calendar: Calendar = .current) -> [DailySwings] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        var totals: [Date: [String: Int]] = [:]
        for activity in activities where activity.date >= start && activity.date < end {
            guard isFullSwing(typename: activity.typename, kind: activity.kind),
                  let strokes = activity.strokeCount, strokes > 0 else { continue }
            let day = calendar.startOfDay(for: activity.date)
            totals[day, default: [:]][kindLabel(activity.kind ?? activity.typename), default: 0] += strokes
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let byKind = totals[day] ?? [:]
            return DailySwings(day: day, count: byKind.values.reduce(0, +), byKind: byKind)
        }
    }

    /// "VIRTUAL_RANGE" -> "Virtual range"
    public static func kindLabel(_ raw: String) -> String {
        let words = raw.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
