import XCTest
@testable import TrackManKit

final class DriverMetricsTests: XCTestCase {
    private let day = utc("2026-11-20T15:00:00Z")

    private func shot(_ club: String, carry: Double, side: Double, ball: Double = 60, at date: Date? = nil) -> ShotSample {
        ShotSample(date: date ?? day, club: club, clubSpeed: 45, ballSpeed: ball, smashFactor: 1.4,
                   launchAngle: 12, spinRate: 2600, carry: carry, total: carry + 20, carrySide: side)
    }

    func testDriverDetection() {
        XCTAssertTrue(DriverMetrics.isDriver("Driver"))
        XCTAssertTrue(DriverMetrics.isDriver("driver"))
        XCTAssertFalse(DriverMetrics.isDriver("7Iron"))
        XCTAssertFalse(DriverMetrics.isDriver(nil))
    }

    func testSummaryUsesDriversOnlyAndConvertsUnits() throws {
        let shots = [
            shot("Driver", carry: 200, side: 0),
            shot("Driver", carry: 220, side: 20),     // 21.9 yd right: a miss
            shot("7Iron", carry: 140, side: -30),     // ignored
        ]
        let summary = DriverMetrics.summary(shots)
        XCTAssertEqual(summary.shots, 2)
        XCTAssertEqual(try XCTUnwrap(summary.carryYards), 210 * Units.yardsPerMeter, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary.ballSpeedMph), 60 * Units.mphPerMetersPerSecond, accuracy: 0.001)
        XCTAssertEqual(summary.missRightShare, 0.5)
        XCTAssertEqual(summary.missLeftShare, 0)
        XCTAssertNotNil(summary.sideSpreadYards)
    }

    func testEmptySummary() {
        let summary = DriverMetrics.summary([])
        XCTAssertEqual(summary.shots, 0)
        XCTAssertNil(summary.carryYards)
        XCTAssertNil(summary.missLeftShare)
    }

    func testDaysGroupsByLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let shots = [
            shot("Driver", carry: 200, side: 0, at: utc("2026-11-20T10:00:00Z")),
            shot("Driver", carry: 210, side: 0, at: utc("2026-11-20T18:00:00Z")),
            shot("Driver", carry: 190, side: 0, at: utc("2026-11-18T10:00:00Z")),
        ]
        let days = DriverMetrics.days(shots, calendar: calendar)
        XCTAssertEqual(days.map(\.shots), [1, 2])
        XCTAssertEqual(try XCTUnwrap(days.last?.carryYards), 205 * Units.yardsPerMeter, accuracy: 0.001)
    }

    func testFairwaySplit() {
        let split = DriverMetrics.fairways([(hit: 4, left: 2, right: 1), (hit: nil, left: nil, right: nil), (hit: 2, left: 0, right: 3)])
        XCTAssertEqual(split, FairwaySplit(hit: 6, left: 2, right: 4))
        XCTAssertEqual(split.hitShare, 0.5)
        XCTAssertNil(FairwaySplit(hit: 0, left: 0, right: 0).hitShare)
    }
}

final class HomeMetricsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func activity(_ id: String, _ time: String, strokes: Int?, kind: String = "VIRTUAL_RANGE", typename: String = "VirtualRangeSessionActivity") -> ActivitySample {
        ActivitySample(id: id, typename: typename, kind: kind, date: utc(time), strokeCount: strokes)
    }

    func testTotalSwingsSkipsPuttingAndRespectsRange() {
        let activities = [
            activity("a", "2026-10-30T10:00:00Z", strokes: 50),
            activity("b", "2026-11-02T10:00:00Z", strokes: 40),
            activity("c", "2026-11-03T10:00:00Z", strokes: 30, kind: "PERFORMANCE_PUTTING", typename: "PerformancePuttingSessionActivity"),
        ]
        XCTAssertEqual(HomeMetrics.totalSwings(activities), 90)
        XCTAssertEqual(HomeMetrics.totalSwings(activities, from: utc("2026-11-01T00:00:00Z"), to: utc("2026-12-01T00:00:00Z")), 40)
    }

    func testMonthLogCoversEveryDayAndCountsSessionsAndRounds() throws {
        let activities = [
            activity("a", "2026-11-02T10:00:00Z", strokes: 40),
            activity("b", "2026-11-02T15:00:00Z", strokes: 20),
            activity("c", "2026-11-05T10:00:00Z", strokes: 12, kind: "PERFORMANCE_PUTTING", typename: "PerformancePuttingSessionActivity"),
            activity("d", "2026-11-07T10:00:00Z", strokes: nil, kind: "COURSE_PLAY", typename: "CoursePlayActivity"),
            activity("e", "2026-10-31T10:00:00Z", strokes: 99),
        ]
        let log = HomeMetrics.monthLog(containing: utc("2026-11-20T00:00:00Z"), activities: activities,
                                       roundDates: [utc("2026-11-07T12:00:00Z")], calendar: calendar)
        XCTAssertEqual(log.count, 30)
        XCTAssertEqual(log[1].swings, 60)
        XCTAssertEqual(log[1].sessions, 2)
        XCTAssertEqual(log[4].swings, 0)      // putting counts as a session, not swings
        XCTAssertEqual(log[4].sessions, 1)
        XCTAssertEqual(log[6].rounds, 1)
        XCTAssertTrue(log[6].isActive)
        XCTAssertEqual(log.filter(\.isActive).count, 3)
    }

    func testStreak() {
        let days: Set<Date> = Set(["2026-11-18", "2026-11-19", "2026-11-20", "2026-11-15"].map { utc("\($0)T00:00:00Z") })
        XCTAssertEqual(HomeMetrics.streak(activeDays: days, today: utc("2026-11-20T15:00:00Z"), calendar: calendar), 3)
        XCTAssertEqual(HomeMetrics.streak(activeDays: days, today: utc("2026-11-21T15:00:00Z"), calendar: calendar), 3)
        XCTAssertEqual(HomeMetrics.streak(activeDays: days, today: utc("2026-11-23T15:00:00Z"), calendar: calendar), 0)
    }
}

final class PhaseThreeAPITests: XCTestCase {
    private func makeAPI(_ responses: [(Int, String)]) -> (TrackManAPI, StubTransport) {
        let transport = StubTransport(responses)
        let provider = TokenProvider(
            refresher: PortalSessionClient(transport: transport, cookies: { [] }),
            store: InMemoryTokenStore(TokenSet(accessToken: "AT", expiresAt: .distantFuture))
        )
        return (TrackManAPI(client: GraphQLClient(transport: transport, tokens: provider)), transport)
    }

    func testStrokesDecodeAndSendNodeID() async throws {
        let json = #"{"data":{"node":{"__typename":"VirtualRangeSessionActivity","strokes":[{"time":"2026-11-17T12:54:39.561704Z","club":"Driver","measurement":{"clubSpeed":45.1,"ballSpeed":65.2,"carry":210.5,"carrySide":-4.2}},{"time":null,"club":"7Iron","measurement":null}]}}}"#
        let (api, transport) = makeAPI([(200, json)])
        let strokes = try await api.strokes(activityID: "node-1")
        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(strokes[0].club, "Driver")
        XCTAssertEqual(strokes[0].measurement?.carry, 210.5)
        XCTAssertNil(strokes[1].measurement)
        let body = try JSONSerialization.jsonObject(with: transport.recorded[0].httpBody!) as! [String: Any]
        XCTAssertEqual((body["variables"] as? [String: Any])?["id"] as? String, "node-1")
    }

    func testStrokesForNodeWithoutShots() async throws {
        let (api, _) = makeAPI([(200, #"{"data":{"node":{"__typename":"CoursePlayActivity"}}}"#)])
        let strokes = try await api.strokes(activityID: "x")
        XCTAssertTrue(strokes.isEmpty)
    }

    func testHandicapDecodes() async throws {
        let (api, _) = makeAPI([(200, #"{"data":{"me":{"hcp":{"currentHcp":14.2}}}}"#), (200, #"{"data":{"me":{"hcp":null}}}"#)])
        let first = try await api.handicap()
        let second = try await api.handicap()
        XCTAssertEqual(first, 14.2)
        XCTAssertNil(second)
    }

    func testScorecardDecodesRoundStats() async throws {
        let json = #"{"data":{"me":{"scorecards":[{"id":"r1","courseHcp":14,"netScore":70,"stat":{"fairwayHitFairway":5,"fairwayHitLeft":3,"fairwayHitRight":2,"numberOfPutts":31}}]}}}"#
        let (api, _) = makeAPI([(200, json)])
        let round = try await api.scorecards(skip: 0, take: 50)[0]
        XCTAssertEqual(round.courseHcp, 14)
        XCTAssertEqual(round.netScore, 70)
        XCTAssertEqual(round.stat?.fairwayHitLeft, 3)
        XCTAssertEqual(round.stat?.numberOfPutts, 31)
    }
}
