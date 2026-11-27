import Foundation

/// Summary statistics for one metric over a set of shots (display units).
public struct MetricStats: Sendable, Equatable {
    public let metric: ShotMetric
    public let count: Int
    public let mean: Double
    public let standardDeviation: Double
    public let min: Double
    public let max: Double
    public let p10: Double
    public let median: Double
    public let p90: Double
}

public struct SessionPoint: Sendable, Equatable, Identifiable {
    public let sessionID: String
    public let date: Date
    public let count: Int
    public let mean: Double
    public var id: String { sessionID }
}

public struct ScatterPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
}

/// How two metrics move together: least-squares line and correlation.
public struct Relationship: Sendable, Equatable {
    public let x: ShotMetric
    public let y: ShotMetric
    public let points: [ScatterPoint]
    public let slope: Double?
    public let intercept: Double?
    /// Pearson correlation, -1...1.
    public let correlation: Double?
}

public struct Bucket: Sendable, Equatable, Identifiable {
    public let label: String
    public let count: Int
    public let share: Double
    public var id: String { label }
}

/// The deterministic analysis toolkit. Every number in a deep dive comes
/// from here, never from the language model.
public enum Analysis {
    public static func values(_ shots: [ShotRecord], _ metric: ShotMetric) -> [Double] {
        shots.compactMap { $0.value(metric) }.filter(\.isFinite)
    }

    public static func stats(_ shots: [ShotRecord], _ metric: ShotMetric) -> MetricStats? {
        let sorted = values(shots, metric).sorted()
        guard !sorted.isEmpty else { return nil }
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let variance = sorted.count > 1
            ? sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(sorted.count - 1)
            : 0
        return MetricStats(
            metric: metric, count: sorted.count, mean: mean, standardDeviation: variance.squareRoot(),
            min: sorted[0], max: sorted[sorted.count - 1],
            p10: percentile(sorted, 0.1), median: percentile(sorted, 0.5), p90: percentile(sorted, 0.9)
        )
    }

    /// Linear interpolation between closest ranks; `sorted` must be ascending.
    public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    /// Mean per session, oldest first, skipping sessions with no values.
    public static func bySession(_ shots: [ShotRecord], _ metric: ShotMetric) -> [SessionPoint] {
        Dictionary(grouping: shots, by: \.sessionID).compactMap { id, group -> SessionPoint? in
            let v = values(group, metric)
            guard !v.isEmpty, let date = group.map(\.date).min() else { return nil }
            return SessionPoint(sessionID: id, date: date, count: v.count, mean: v.reduce(0, +) / Double(v.count))
        }
        .sorted { $0.date < $1.date }
    }

    public static func relationship(_ shots: [ShotRecord], x: ShotMetric, y: ShotMetric) -> Relationship {
        let points = shots.compactMap { shot -> ScatterPoint? in
            guard let a = shot.value(x), let b = shot.value(y), a.isFinite, b.isFinite else { return nil }
            return ScatterPoint(x: a, y: b)
        }
        guard points.count >= 3 else {
            return Relationship(x: x, y: y, points: points, slope: nil, intercept: nil, correlation: nil)
        }
        let n = Double(points.count)
        let mx = points.map(\.x).reduce(0, +) / n
        let my = points.map(\.y).reduce(0, +) / n
        let sxy = points.map { ($0.x - mx) * ($0.y - my) }.reduce(0, +)
        let sxx = points.map { ($0.x - mx) * ($0.x - mx) }.reduce(0, +)
        let syy = points.map { ($0.y - my) * ($0.y - my) }.reduce(0, +)
        let slope = sxx > 0 ? sxy / sxx : nil
        let correlation = sxx > 0 && syy > 0 ? sxy / (sxx * syy).squareRoot() : nil
        return Relationship(x: x, y: y, points: points, slope: slope, intercept: slope.map { my - $0 * mx }, correlation: correlation)
    }

    /// Splits values at `edges` (ascending) into labeled buckets; `labels`
    /// has one more entry than `edges`.
    public static func buckets(_ shots: [ShotRecord], _ metric: ShotMetric, edges: [Double], labels: [String]) -> [Bucket] {
        precondition(labels.count == edges.count + 1)
        let v = values(shots, metric)
        var counts = Array(repeating: 0, count: labels.count)
        for value in v {
            let index = edges.firstIndex { value < $0 } ?? edges.count
            counts[index] += 1
        }
        return zip(labels, counts).map { label, count in
            Bucket(label: label, count: count, share: v.isEmpty ? 0 : Double(count) / Double(v.count))
        }
    }

    /// Histogram bins of equal width covering the values.
    public static func histogram(_ shots: [ShotRecord], _ metric: ShotMetric, bins: Int = 12) -> [HistogramBin] {
        let v = values(shots, metric)
        guard let low = v.min(), let high = v.max(), bins > 0 else { return [] }
        let width = high > low ? (high - low) / Double(bins) : 1
        var counts = Array(repeating: 0, count: bins)
        for value in v {
            counts[Swift.min(Int((value - low) / width), bins - 1)] += 1
        }
        return counts.enumerated().map { i, count in
            HistogramBin(lower: low + Double(i) * width, upper: low + Double(i + 1) * width, count: count)
        }
    }

    /// Metrics that have at least one value in these shots.
    public static func available(_ shots: [ShotRecord]) -> Set<ShotMetric> {
        Set(shots.flatMap { $0.values.keys })
    }
}

public struct HistogramBin: Sendable, Equatable, Identifiable {
    public let lower: Double
    public let upper: Double
    public let count: Int
    public var id: Double { lower }
    public var mid: Double { (lower + upper) / 2 }
}
