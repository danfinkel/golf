import Foundation

/// The preset deep dives. "Other" questions reuse the same building blocks
/// through the on-device model's tool calls.
public enum DeepDiveTopic: String, CaseIterable, Codable, Sendable, Identifiable {
    case path, speed, strike, shape
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .path: return "Swing path"
        case .speed: return "Swing speed"
        case .strike: return "Face strike"
        case .shape: return "Slice and hook"
        }
    }

    public var blurb: String {
        switch self {
        case .path: return "Club path, face angle and how they line up."
        case .speed: return "Club and ball speed, smash, and what speed buys you."
        case .strike: return "Where you hit the face and what it costs."
        case .shape: return "How the ball curves and what causes it."
        }
    }

    public var symbol: String {
        switch self {
        case .path: return "arrow.triangle.swap"
        case .speed: return "speedometer"
        case .strike: return "scope"
        case .shape: return "arrow.uturn.right"
        }
    }

    /// Metrics the topic needs; a report notes any that were not measured.
    public var metrics: [ShotMetric] {
        switch self {
        case .path: return [.clubPath, .faceAngle, .faceToPath]
        case .speed: return [.clubSpeed, .ballSpeed, .smashFactor, .carry]
        case .strike: return [.impactOffset, .impactHeight, .smashFactor]
        case .shape: return [.faceToPath, .spinAxis, .carrySide]
        }
    }
}

public struct KeyStat: Sendable, Equatable, Identifiable {
    public let label: String
    public let value: String
    public let detail: String?
    public var id: String { label }
}

public enum DeepDiveChart: Sendable, Equatable, Identifiable {
    case histogram(title: String, metric: ShotMetric, bins: [HistogramBin])
    case trend(title: String, metric: ShotMetric, points: [SessionPoint])
    case scatter(title: String, relationship: Relationship)
    case buckets(title: String, buckets: [Bucket])
    /// Impact location: x is toe/heel, y is high/low, both mm.
    case strikeMap(title: String, points: [ScatterPoint])

    public var title: String {
        switch self {
        case .histogram(let t, _, _), .trend(let t, _, _), .scatter(let t, _), .buckets(let t, _), .strikeMap(let t, _): return t
        }
    }
    public var id: String { title }
}

/// A finished analysis: numbers, charts and plain-language findings, all
/// computed in code. `facts` is the compact text handed to the language
/// model, which may only restate these.
public struct DeepDiveReport: Sendable, Equatable {
    public let topic: DeepDiveTopic
    public let club: String?
    public let shotCount: Int
    public let sessionCount: Int
    public let keyStats: [KeyStat]
    public let charts: [DeepDiveChart]
    public let findings: [String]
    public let missing: [ShotMetric]

    public var facts: [String] { keyStats.map { "\($0.label): \($0.value)\($0.detail.map { " (\($0))" } ?? "")" } + findings }
}

public enum DeepDive {
    /// Shots needed before a finding is worth stating.
    public static let minimumShots = 8

    public static func run(_ topic: DeepDiveTopic, shots: [ShotRecord], club: String?) -> DeepDiveReport {
        let selected = club.map { name in shots.filter { $0.club == name } } ?? shots
        let available = Analysis.available(selected)
        let missing = topic.metrics.filter { !available.contains($0) }
        let sessions = Set(selected.map(\.sessionID)).count
        var stats: [KeyStat] = []
        var charts: [DeepDiveChart] = []
        var findings: [String] = []

        switch topic {
        case .path: path(selected, &stats, &charts, &findings)
        case .speed: speed(selected, club: club, &stats, &charts, &findings)
        case .strike: strike(selected, &stats, &charts, &findings)
        case .shape: shape(selected, &stats, &charts, &findings)
        }
        if selected.count < minimumShots {
            findings = ["Only \(selected.count) shots: pick more sessions for findings you can trust."]
        }
        return DeepDiveReport(topic: topic, club: club, shotCount: selected.count, sessionCount: sessions,
                              keyStats: stats, charts: charts, findings: findings, missing: missing)
    }

    // MARK: Presets

    static func path(_ shots: [ShotRecord], _ stats: inout [KeyStat], _ charts: inout [DeepDiveChart], _ findings: inout [String]) {
        guard let path = Analysis.stats(shots, .clubPath) else { return }
        stats.append(KeyStat(label: "Club path", value: signedDegrees(path.mean, positive: "in-to-out", negative: "out-to-in"),
                             detail: "±\(f(path.standardDeviation, 1))° shot to shot"))
        if let face = Analysis.stats(shots, .faceAngle) {
            stats.append(KeyStat(label: "Face angle", value: signedDegrees(face.mean, positive: "open", negative: "closed"), detail: "to target"))
        }
        if let ftp = Analysis.stats(shots, .faceToPath) {
            stats.append(KeyStat(label: "Face to path", value: signedDegrees(ftp.mean, positive: "open", negative: "closed"), detail: "to path"))
        }
        let split = Analysis.buckets(shots, .clubPath, edges: [-2, 2], labels: ["Out-to-in", "Neutral", "In-to-out"])
        charts.append(.buckets(title: "Path direction", buckets: split))
        charts.append(.histogram(title: "Club path", metric: .clubPath, bins: Analysis.histogram(shots, .clubPath)))
        let sessions = Analysis.bySession(shots, .clubPath)
        if sessions.count >= 2 { charts.append(.trend(title: "Path by session", metric: .clubPath, points: sessions)) }
        let faceVsPath = Analysis.relationship(shots, x: .clubPath, y: .faceAngle)
        if faceVsPath.points.count >= 3 { charts.append(.scatter(title: "Face vs path", relationship: faceVsPath)) }

        if let top = split.max(by: { $0.share < $1.share }) {
            findings.append("\(pct(top.share)) of swings are \(top.label.lowercased()), averaging \(signedDegrees(path.mean, positive: "in-to-out", negative: "out-to-in")).")
        }
        findings.append(path.standardDeviation > 3
            ? "Path varies a lot (±\(f(path.standardDeviation, 1))°), so start lines will scatter. Consistency is the first thing to work on."
            : "Path is consistent (±\(f(path.standardDeviation, 1))°).")
        if let ftp = Analysis.stats(shots, .faceToPath), abs(ftp.mean) >= 1.5 {
            findings.append("The face is \(f(abs(ftp.mean), 1))° \(ftp.mean > 0 ? "open" : "closed") to the path on average, which curves the ball \(ftp.mean > 0 ? "right (fade or slice)" : "left (draw or hook)").")
        }
        if let change = sessionChange(sessions), abs(change) >= 1 {
            findings.append("Path moved \(f(abs(change), 1))° \(change > 0 ? "more in-to-out" : "more out-to-in") from your earliest to latest sessions.")
        }
    }

    static func speed(_ shots: [ShotRecord], club: String?, _ stats: inout [KeyStat], _ charts: inout [DeepDiveChart], _ findings: inout [String]) {
        guard let speed = Analysis.stats(shots, .clubSpeed) else { return }
        stats.append(KeyStat(label: "Club speed", value: ShotMetric.clubSpeed.format(speed.mean), detail: "Top 10%: \(ShotMetric.clubSpeed.format(speed.p90))"))
        if let ball = Analysis.stats(shots, .ballSpeed) {
            stats.append(KeyStat(label: "Ball speed", value: ShotMetric.ballSpeed.format(ball.mean), detail: nil))
        }
        if let smash = Analysis.stats(shots, .smashFactor) {
            stats.append(KeyStat(label: "Smash", value: ShotMetric.smashFactor.format(smash.mean), detail: "±\(f(smash.standardDeviation, 2))"))
            if let club, DriverMetrics.isDriver(club) {
                findings.append(smash.mean >= 1.45
                    ? "Smash of \(f(smash.mean, 2)) means you are turning speed into ball speed well."
                    : "Smash averages \(f(smash.mean, 2)); good driver contact is around 1.45 to 1.50, so centered strikes would add ball speed without swinging harder.")
            }
        }
        let sessions = Analysis.bySession(shots, .clubSpeed)
        if sessions.count >= 2 { charts.append(.trend(title: "Club speed by session", metric: .clubSpeed, points: sessions)) }
        charts.append(.histogram(title: "Club speed", metric: .clubSpeed, bins: Analysis.histogram(shots, .clubSpeed)))
        let carry = Analysis.relationship(shots, x: .clubSpeed, y: .carry)
        if carry.points.count >= 3 { charts.append(.scatter(title: "Carry vs club speed", relationship: carry)) }

        findings.append("Your fastest 10% of swings are \(f(speed.p90 - speed.mean, 1)) mph above your average.")
        if let slope = carry.slope, let r = carry.correlation, r > 0.3 {
            findings.append("Each extra mph of club speed has meant about \(f(slope, 1)) more yards of carry.")
        }
        if let change = sessionChange(sessions), abs(change) >= 1 {
            findings.append("Club speed is \(change > 0 ? "up" : "down") \(f(abs(change), 1)) mph from your earliest to latest sessions.")
        }
    }

    static func strike(_ shots: [ShotRecord], _ stats: inout [KeyStat], _ charts: inout [DeepDiveChart], _ findings: inout [String]) {
        let map = shots.compactMap { shot -> ScatterPoint? in
            guard let x = shot.value(.impactOffset), let y = shot.value(.impactHeight) else { return nil }
            return ScatterPoint(x: x, y: y)
        }
        if let offset = Analysis.stats(shots, .impactOffset) {
            stats.append(KeyStat(label: "Toe/heel", value: signedMM(offset.mean, positive: "toward toe", negative: "toward heel"), detail: "±\(f(offset.standardDeviation, 0)) mm"))
            let split = Analysis.buckets(shots, .impactOffset, edges: [-10, 10], labels: ["Heel", "Center", "Toe"])
            charts.append(.buckets(title: "Strike location", buckets: split))
            if let center = split.first(where: { $0.label == "Center" }) {
                findings.append("\(pct(center.share)) of strikes land within 10 mm of the center, toe to heel.")
            }
            let smash = Analysis.relationship(shots, x: .impactOffset, y: .smashFactor)
            if smash.points.count >= 3 { charts.append(.scatter(title: "Smash vs strike", relationship: smash)) }
        }
        if let height = Analysis.stats(shots, .impactHeight) {
            stats.append(KeyStat(label: "High/low", value: signedMM(height.mean, positive: "high", negative: "low"), detail: "±\(f(height.standardDeviation, 0)) mm"))
        }
        if !map.isEmpty { charts.insert(.strikeMap(title: "Strike map", points: map), at: 0) }

        // Without impact location, fall back to smash consistency.
        if map.isEmpty, let smash = Analysis.stats(shots, .smashFactor) {
            stats.append(KeyStat(label: "Smash", value: ShotMetric.smashFactor.format(smash.mean), detail: "±\(f(smash.standardDeviation, 2))"))
            charts.append(.histogram(title: "Smash factor", metric: .smashFactor, bins: Analysis.histogram(shots, .smashFactor)))
            findings.append("These sessions have no impact location, so strike quality is judged from smash factor: \(f(smash.p10, 2)) on your worst 10% against \(f(smash.p90, 2)) on your best.")
        }
    }

    static func shape(_ shots: [ShotRecord], _ stats: inout [KeyStat], _ charts: inout [DeepDiveChart], _ findings: inout [String]) {
        if let axis = Analysis.stats(shots, .spinAxis) {
            stats.append(KeyStat(label: "Spin axis", value: signedDegrees(axis.mean, positive: "right", negative: "left"), detail: "±\(f(axis.standardDeviation, 1))°"))
            let split = Analysis.buckets(shots, .spinAxis, edges: [-10, -3, 3, 10], labels: ["Hook", "Draw", "Straight", "Fade", "Slice"])
            charts.append(.buckets(title: "Ball flight", buckets: split))
            let slice = split.last?.share ?? 0
            let hook = split.first?.share ?? 0
            if slice >= 0.2 { findings.append("\(pct(slice)) of shots slice (spin axis over 10° right).") }
            if hook >= 0.2 { findings.append("\(pct(hook)) of shots hook (spin axis over 10° left).") }
            if slice < 0.2 && hook < 0.2 { findings.append("Big curves are rare: \(pct(slice + hook)) of shots slice or hook.") }
        }
        if let ftp = Analysis.stats(shots, .faceToPath) {
            stats.append(KeyStat(label: "Face to path", value: signedDegrees(ftp.mean, positive: "open", negative: "closed"), detail: nil))
        }
        if let side = Analysis.stats(shots, .carrySide) {
            stats.append(KeyStat(label: "Carry side", value: signedYards(side.mean), detail: "±\(f(side.standardDeviation, 0)) yd"))
        }
        let cause = Analysis.relationship(shots, x: .faceToPath, y: .spinAxis)
        if cause.points.count >= 3 {
            charts.append(.scatter(title: "Curve vs face to path", relationship: cause))
            if let r = cause.correlation, r > 0.6, let slope = cause.slope {
                findings.append("Face to path explains your curve well (r = \(f(r, 2))): each degree open adds about \(f(slope, 1))° of spin axis.")
            }
        }
        let sessions = Analysis.bySession(shots, .spinAxis)
        if sessions.count >= 2 { charts.append(.trend(title: "Spin axis by session", metric: .spinAxis, points: sessions)) }
    }

    // MARK: Helpers

    static func sessionChange(_ points: [SessionPoint]) -> Double? {
        guard points.count >= 2 else { return nil }
        let half = max(1, points.count / 2)
        let early = points.prefix(half).map(\.mean)
        let late = points.suffix(half).map(\.mean)
        return late.reduce(0, +) / Double(late.count) - early.reduce(0, +) / Double(early.count)
    }

    static func f(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func pct(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    static func signedDegrees(_ value: Double, positive: String, negative: String) -> String {
        abs(value) < 0.05 ? "0.0°" : "\(f(abs(value), 1))° \(value > 0 ? positive : negative)"
    }

    static func signedMM(_ value: Double, positive: String, negative: String) -> String {
        abs(value) < 0.5 ? "Centered" : "\(f(abs(value), 0)) mm \(value > 0 ? positive : negative)"
    }

    static func signedYards(_ value: Double) -> String {
        abs(value) < 0.5 ? "On line" : "\(f(abs(value), 0)) yd \(value > 0 ? "right" : "left")"
    }
}
