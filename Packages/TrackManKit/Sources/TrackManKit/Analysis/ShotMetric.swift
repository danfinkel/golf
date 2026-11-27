import Foundation

/// A measured number on a shot, with how to show it. Values are stored in
/// TrackMan's units (m/s, meters, degrees, rpm) and converted for display.
///
/// Signs follow TrackMan for a right-handed golfer: positive club path is
/// in-to-out, positive face angle and face-to-path point right, positive
/// spin axis and side are right of target.
public enum ShotMetric: String, CaseIterable, Codable, Sendable {
    case clubSpeed, ballSpeed, smashFactor
    case attackAngle, clubPath, faceAngle, faceToPath, dynamicLoft
    case launchAngle, launchDirection, spinRate, spinAxis
    case carry, total, carrySide, totalSide, curve, maxHeight
    case impactOffset, impactHeight

    public var label: String {
        switch self {
        case .clubSpeed: return "Club speed"
        case .ballSpeed: return "Ball speed"
        case .smashFactor: return "Smash factor"
        case .attackAngle: return "Attack angle"
        case .clubPath: return "Club path"
        case .faceAngle: return "Face angle"
        case .faceToPath: return "Face to path"
        case .dynamicLoft: return "Dynamic loft"
        case .launchAngle: return "Launch angle"
        case .launchDirection: return "Launch direction"
        case .spinRate: return "Spin rate"
        case .spinAxis: return "Spin axis"
        case .carry: return "Carry"
        case .total: return "Total"
        case .carrySide: return "Carry side"
        case .totalSide: return "Total side"
        case .curve: return "Curve"
        case .maxHeight: return "Height"
        case .impactOffset: return "Strike toe/heel"
        case .impactHeight: return "Strike high/low"
        }
    }

    public var unit: String {
        switch self {
        case .clubSpeed, .ballSpeed: return "mph"
        case .smashFactor: return ""
        case .attackAngle, .clubPath, .faceAngle, .faceToPath, .dynamicLoft, .launchAngle, .launchDirection, .spinAxis: return "°"
        case .spinRate: return "rpm"
        case .carry, .total, .carrySide, .totalSide, .curve, .maxHeight: return "yd"
        case .impactOffset, .impactHeight: return "mm"
        }
    }

    /// TrackMan value to display value.
    public func display(_ raw: Double) -> Double {
        switch self {
        case .clubSpeed, .ballSpeed: return raw * Units.mphPerMetersPerSecond
        case .carry, .total, .carrySide, .totalSide, .curve, .maxHeight: return raw * Units.yardsPerMeter
        case .impactOffset, .impactHeight: return raw * 1000
        default: return raw
        }
    }

    /// Digits after the decimal point when shown.
    public var precision: Int {
        switch self {
        case .smashFactor: return 2
        case .clubSpeed, .ballSpeed, .carry, .total, .spinRate, .maxHeight: return 0
        default: return 1
        }
    }

    public func format(_ displayValue: Double) -> String {
        let number = displayValue.formatted(.number.precision(.fractionLength(precision)))
        switch unit {
        case "": return number
        case "°": return number + "°"
        default: return number + " " + unit
        }
    }
}

/// One shot as the deep dive sees it: who, when, which club, and every
/// measured number (in TrackMan units).
public struct ShotRecord: Sendable, Equatable {
    public let sessionID: String
    public let date: Date
    public let club: String
    public let values: [ShotMetric: Double]

    public init(sessionID: String, date: Date, club: String, values: [ShotMetric: Double]) {
        self.sessionID = sessionID
        self.date = date
        self.club = club
        self.values = values
    }

    /// The value in display units, or nil when TrackMan did not measure it.
    public func value(_ metric: ShotMetric) -> Double? {
        values[metric].map(metric.display)
    }
}
