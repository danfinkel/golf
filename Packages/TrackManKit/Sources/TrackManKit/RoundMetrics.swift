import Foundation

public enum RoundMetrics {
    /// A round counts when TrackMan marks it completed, or, failing that,
    /// when a full 9 or 18 holes were played.
    public static func isFinished(isCompleted: Bool?, holesPlayed: Int?) -> Bool {
        if isCompleted == true { return true }
        return holesPlayed == 9 || holesPlayed == 18
    }

    /// "+3", "-1", "E"
    public static func toParLabel(_ toPar: Int) -> String {
        toPar == 0 ? "E" : toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }

    /// Score relative to par on one hole, for scorecard styling.
    public enum HoleResult: Equatable, Sendable {
        case eagleOrBetter, birdie, par, bogey, doubleOrWorse
    }

    public static func result(score: Int?, par: Int?) -> HoleResult? {
        guard let score, let par, score > 0 else { return nil }
        switch score - par {
        case ...(-2): return .eagleOrBetter
        case -1: return .birdie
        case 0: return .par
        case 1: return .bogey
        default: return .doubleOrWorse
        }
    }

    /// Holes split into the nines a scorecard prints: 1-9 then 10-18.
    public static func nines(_ holes: [Scorecard.Hole]) -> [[Scorecard.Hole]] {
        let sorted = holes.sorted { ($0.holeNumber ?? 0) < ($1.holeNumber ?? 0) }
        let front = sorted.filter { ($0.holeNumber ?? 0) <= 9 }
        let back = sorted.filter { ($0.holeNumber ?? 0) > 9 }
        return [front, back].filter { !$0.isEmpty }
    }

    /// Sum of a nine, counting only holes that have a value.
    public static func total(_ holes: [Scorecard.Hole], _ key: KeyPath<Scorecard.Hole, Int?>) -> Int? {
        let values = holes.compactMap { $0[keyPath: key] }.filter { $0 > 0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

/// One club's averages for a set of shots, in display units.
public struct ClubLine: Sendable, Equatable, Identifiable {
    public let club: String
    public let shots: Int
    public let carryYards: Double?
    public let ballSpeedMph: Double?
    public var id: String { club }
}

public enum ClubMetrics {
    /// Shots grouped by club, longest average carry first.
    public static func lines(_ shots: [ShotSample]) -> [ClubLine] {
        Dictionary(grouping: shots, by: \.club).map { club, group in
            let carries = group.compactMap(\.carry)
            let speeds = group.compactMap(\.ballSpeed)
            return ClubLine(
                club: club,
                shots: group.count,
                carryYards: carries.isEmpty ? nil : Units.yards(fromMeters: carries.reduce(0, +) / Double(carries.count)),
                ballSpeedMph: speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count) * Units.mphPerMetersPerSecond
            )
        }
        .sorted { ($0.carryYards ?? -1, $1.club) > ($1.carryYards ?? -1, $0.club) }
    }

    /// "7Iron" -> "7 Iron", "PitchingWedge" -> "Pitching Wedge"
    public static func label(_ club: String) -> String {
        var result = ""
        for (index, char) in club.enumerated() {
            if index > 0, char.isUppercase || (char.isLetter && result.last?.isNumber == true) {
                result.append(" ")
            }
            result.append(char)
        }
        return result
    }
}
