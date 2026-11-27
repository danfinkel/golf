import Foundation

/// One practice shot in SI units, independent of the API and the database.
public struct ShotSample: Sendable, Equatable {
    public let date: Date
    public let club: String
    public let clubSpeed: Double?   // m/s
    public let ballSpeed: Double?   // m/s
    public let smashFactor: Double?
    public let launchAngle: Double? // degrees
    public let attackAngle: Double? // degrees
    public let spinRate: Double?    // rpm
    public let carry: Double?       // meters
    public let total: Double?       // meters
    public let carrySide: Double?   // meters, negative is left

    public init(date: Date, club: String, clubSpeed: Double? = nil, ballSpeed: Double? = nil, smashFactor: Double? = nil,
                launchAngle: Double? = nil, attackAngle: Double? = nil, spinRate: Double? = nil,
                carry: Double? = nil, total: Double? = nil, carrySide: Double? = nil) {
        self.date = date
        self.club = club
        self.clubSpeed = clubSpeed
        self.ballSpeed = ballSpeed
        self.smashFactor = smashFactor
        self.launchAngle = launchAngle
        self.attackAngle = attackAngle
        self.spinRate = spinRate
        self.carry = carry
        self.total = total
        self.carrySide = carrySide
    }
}

/// Averages over a set of driver shots, in display units (mph, yards).
public struct DriverSummary: Sendable, Equatable {
    public let shots: Int
    public let clubSpeedMph: Double?
    public let ballSpeedMph: Double?
    public let smashFactor: Double?
    public let launchAngle: Double?
    public let attackAngle: Double?
    public let spinRate: Double?
    public let carryYards: Double?
    public let totalYards: Double?
    /// Standard deviation of carry side: how wide the shots spread.
    public let sideSpreadYards: Double?
    /// Share of shots finishing more than 15 yards left or right of target.
    public let missLeftShare: Double?
    public let missRightShare: Double?
}

/// One practice day's driver averages, for the trend chart.
public struct DriverDay: Sendable, Equatable, Identifiable {
    public let day: Date
    public let shots: Int
    public let carryYards: Double?
    public let ballSpeedMph: Double?
    public var id: Date { day }
}

/// Tee-shot results summed over course rounds.
public struct FairwaySplit: Sendable, Equatable {
    public let hit: Int
    public let left: Int
    public let right: Int
    public var total: Int { hit + left + right }
    public var hitShare: Double? { total > 0 ? Double(hit) / Double(total) : nil }
}

public enum DriverMetrics {
    /// Yards off line that count as a miss.
    public static let missYards = 15.0

    /// TrackMan names the club "Driver"; anything else is not a driver.
    public static func isDriver(_ club: String?) -> Bool {
        (club ?? "").caseInsensitiveCompare("Driver") == .orderedSame
    }

    public static func summary(_ shots: [ShotSample]) -> DriverSummary {
        let drives = shots.filter { isDriver($0.club) }
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func avg(_ key: KeyPath<ShotSample, Double?>, scale: Double = 1) -> Double? {
            mean(drives.compactMap { $0[keyPath: key] }.map { $0 * scale })
        }
        let sides = drives.compactMap(\.carrySide).map(Units.yards(fromMeters:))
        var spread: Double?
        if sides.count >= 2, let m = mean(sides) {
            spread = (sides.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(sides.count - 1)).squareRoot()
        }
        let left = sides.isEmpty ? nil : Double(sides.filter { $0 < -missYards }.count) / Double(sides.count)
        let right = sides.isEmpty ? nil : Double(sides.filter { $0 > missYards }.count) / Double(sides.count)
        return DriverSummary(
            shots: drives.count,
            clubSpeedMph: avg(\.clubSpeed, scale: Units.mphPerMetersPerSecond),
            ballSpeedMph: avg(\.ballSpeed, scale: Units.mphPerMetersPerSecond),
            smashFactor: avg(\.smashFactor),
            launchAngle: avg(\.launchAngle),
            attackAngle: avg(\.attackAngle),
            spinRate: avg(\.spinRate),
            carryYards: avg(\.carry, scale: Units.yardsPerMeter),
            totalYards: avg(\.total, scale: Units.yardsPerMeter),
            sideSpreadYards: spread,
            missLeftShare: left,
            missRightShare: right
        )
    }

    /// Driver averages per local calendar day that had driver shots, oldest first.
    public static func days(_ shots: [ShotSample], calendar: Calendar = .current) -> [DriverDay] {
        let grouped = Dictionary(grouping: shots.filter { isDriver($0.club) }) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            let summary = summary(grouped[day] ?? [])
            return DriverDay(day: day, shots: summary.shots, carryYards: summary.carryYards, ballSpeedMph: summary.ballSpeedMph)
        }
    }

    public static func fairways(_ rounds: [(hit: Int?, left: Int?, right: Int?)]) -> FairwaySplit {
        FairwaySplit(
            hit: rounds.compactMap(\.hit).reduce(0, +),
            left: rounds.compactMap(\.left).reduce(0, +),
            right: rounds.compactMap(\.right).reduce(0, +)
        )
    }
}
