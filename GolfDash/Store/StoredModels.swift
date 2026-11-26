import Foundation
import SwiftData
import TrackManKit

/// A course round cached on device. Distances stay in meters, as TrackMan
/// returns them, and are converted for display.
@Model
final class StoredRound {
    @Attribute(.unique) var id: String
    var date: Date
    var courseName: String?
    var teeName: String?
    var holesPlayed: Int?
    var isCompleted: Bool
    var grossScore: Int?
    var toPar: Int?
    var driveAverageMeters: Double?
    var driveMaxMeters: Double?

    init(id: String, date: Date) {
        self.id = id
        self.date = date
        self.isCompleted = false
    }

    func update(from card: Scorecard, date: Date) {
        self.date = date
        courseName = card.course?.displayName?.trimmingCharacters(in: .whitespaces)
        teeName = card.teeName
        holesPlayed = card.numberOfHolesPlayed
        isCompleted = card.isCompleted ?? false
        grossScore = card.grossScore
        toPar = card.toPar
        driveAverageMeters = card.stat?.driveAverage
        driveMaxMeters = card.stat?.driveMax
    }

    var sample: RoundSample { RoundSample(id: id, date: date, driveAverageMeters: driveAverageMeters) }
}

@Model
final class StoredActivity {
    @Attribute(.unique) var id: String
    var typename: String
    var kind: String?
    var date: Date
    var strokeCount: Int?

    init(id: String, typename: String, date: Date) {
        self.id = id
        self.typename = typename
        self.date = date
    }

    func update(from activity: Activity, date: Date) {
        typename = activity.typename
        kind = activity.kind
        self.date = date
        strokeCount = activity.strokeCount
    }

    var sample: ActivitySample {
        ActivitySample(id: id, typename: typename, kind: kind, date: date, strokeCount: strokeCount)
    }
}
