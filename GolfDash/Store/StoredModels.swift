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
    var netScore: Int?
    var courseHandicap: Double?
    var fairwaysHit: Int?
    var fairwaysLeft: Int?
    var fairwaysRight: Int?
    var greensInRegulation: Int?
    var putts: Int?
    var topBallSpeedMetersPerSecond: Double?
    var outScore: Int?
    var inScore: Int?
    var eagles: Int?
    var birdies: Int?
    var pars: Int?
    var bogeys: Int?
    var doubleBogeys: Int?
    var triplesOrWorse: Int?
    /// The scorecard's holes as JSON; nil until a sync has fetched them.
    var holesData: Data?

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
        netScore = card.netScore
        courseHandicap = card.courseHcp
        fairwaysHit = card.stat?.fairwayHitFairway
        fairwaysLeft = card.stat?.fairwayHitLeft
        fairwaysRight = card.stat?.fairwayHitRight
        greensInRegulation = card.stat?.greenInRegulation
        putts = card.stat?.numberOfPutts
        topBallSpeedMetersPerSecond = card.stat?.highestBallSpeed
        outScore = card.outScore
        inScore = card.inScore
        eagles = card.stat?.eagles
        birdies = card.stat?.birdies
        pars = card.stat?.pars
        bogeys = card.stat?.bogeys
        doubleBogeys = card.stat?.doubleBogeys
        triplesOrWorse = card.stat?.tripleBogeysOrWorse
        holesData = try? JSONEncoder().encode(card.holes ?? [])
    }

    var holes: [Scorecard.Hole] {
        guard let holesData else { return [] }
        return (try? JSONDecoder().decode([Scorecard.Hole].self, from: holesData)) ?? []
    }

    /// Completed, or a full 9 or 18 holes. Unfinished rounds are left out
    /// of every screen and stat.
    var isFinished: Bool { RoundMetrics.isFinished(isCompleted: isCompleted, holesPlayed: holesPlayed) }

    var toParLabel: String? { toPar.map(RoundMetrics.toParLabel) }

    var sample: RoundSample { RoundSample(id: id, date: date, driveAverageMeters: driveAverageMeters) }
}

@Model
final class StoredActivity {
    @Attribute(.unique) var id: String
    var typename: String
    var kind: String?
    var date: Date
    var strokeCount: Int?
    /// True once this session's shots are stored as StoredShot rows.
    var shotsFetched: Bool = false

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

/// One practice shot, kept in TrackMan's SI units.
@Model
final class StoredShot {
    /// "<activity id>#<index>", stable across syncs.
    @Attribute(.unique) var id: String
    var activityID: String
    var date: Date
    var club: String
    var clubSpeed: Double?
    var ballSpeed: Double?
    var smashFactor: Double?
    var launchAngle: Double?
    var attackAngle: Double?
    var spinRate: Double?
    var carry: Double?
    var total: Double?
    var carrySide: Double?

    init(activityID: String, index: Int, sessionDate: Date, stroke: Stroke) {
        id = "\(activityID)#\(index)"
        self.activityID = activityID
        date = stroke.date ?? sessionDate
        club = stroke.club ?? "Unknown"
        let m = stroke.measurement
        clubSpeed = m?.clubSpeed
        ballSpeed = m?.ballSpeed
        smashFactor = m?.smashFactor
        launchAngle = m?.launchAngle
        attackAngle = m?.attackAngle
        spinRate = m?.spinRate
        carry = m?.carry
        total = m?.total
        carrySide = m?.carrySide
    }

    var sample: ShotSample {
        ShotSample(date: date, club: club, clubSpeed: clubSpeed, ballSpeed: ballSpeed, smashFactor: smashFactor,
                   launchAngle: launchAngle, attackAngle: attackAngle, spinRate: spinRate,
                   carry: carry, total: total, carrySide: carrySide)
    }
}
