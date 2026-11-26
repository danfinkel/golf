import XCTest
@testable import TrackManKit

final class MetricsTests: XCTestCase {
    private func meters(_ yards: Double) -> Double { yards / Units.yardsPerMeter }

    func testDriveTrendSortsOldestFirstAndRollsOverFiveRounds() {
        // Given newest first, as TrackMan returns them.
        let yards: [Double] = [200, 190, 180, 170, 160, 150]
        let rounds = yards.enumerated().map { index, value in
            RoundSample(id: "r\(index)", date: Date(timeIntervalSince1970: Double(100 - index) * 86_400), driveAverageMeters: meters(value))
        }

        let trend = Metrics.driveTrend(rounds)

        XCTAssertEqual(trend.map(\.id), ["r5", "r4", "r3", "r2", "r1", "r0"])
        XCTAssertEqual(trend[0].yards, 150, accuracy: 1e-9)
        XCTAssertNil(trend[3].rollingYards)
        XCTAssertEqual(trend[4].rollingYards!, 170, accuracy: 1e-9) // 150...190
        XCTAssertEqual(trend[5].rollingYards!, 180, accuracy: 1e-9) // 160...200
        XCTAssertEqual(Metrics.headlineDrive(trend)!, 180, accuracy: 1e-9)
    }

    func testDriveTrendSkipsRoundsWithoutDriveData() {
        let rounds = [
            RoundSample(id: "a", date: Date(timeIntervalSince1970: 1), driveAverageMeters: nil),
            RoundSample(id: "b", date: Date(timeIntervalSince1970: 2), driveAverageMeters: 0),
            RoundSample(id: "c", date: Date(timeIntervalSince1970: 3), driveAverageMeters: meters(200)),
            RoundSample(id: "d", date: Date(timeIntervalSince1970: 4), driveAverageMeters: meters(210)),
        ]
        let trend = Metrics.driveTrend(rounds)
        XCTAssertEqual(trend.map(\.id), ["c", "d"])
        XCTAssertEqual(Metrics.headlineDrive(trend)!, 205, accuracy: 1e-9)
        XCTAssertNil(Metrics.headlineDrive([]))
    }

    func testMeterConversionMatchesPOC() {
        // course_play.py: round(166.25 * 1.0936132983, 1) == 181.8
        XCTAssertEqual((Units.yards(fromMeters: 166.25) * 10).rounded() / 10, 181.8)
    }

    func testDailySwingsBucketsLocalDaysAndExcludesPutting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = utc("2026-11-26T15:00:00Z") // 10 AM Nov 26 in New York

        let activities = [
            // 01:00Z Nov 26 is 8 PM Nov 25 in New York.
            ActivitySample(id: "1", typename: "VirtualRangeSessionActivity", kind: "VIRTUAL_RANGE", date: utc("2026-11-26T01:00:00Z"), strokeCount: 40),
            ActivitySample(id: "2", typename: "SimulatorSessionActivity", kind: "SIMULATOR", date: utc("2026-11-25T14:00:00Z"), strokeCount: 10),
            ActivitySample(id: "3", typename: "PerformancePuttingSessionActivity", kind: "PERFORMANCE_PUTTING", date: utc("2026-11-25T14:00:00Z"), strokeCount: 99),
            ActivitySample(id: "4", typename: "VirtualRangeSessionActivity", kind: "VIRTUAL_RANGE", date: utc("2026-11-26T14:00:00Z"), strokeCount: 5),
            ActivitySample(id: "5", typename: "CoursePlayActivity", kind: "COURSE_PLAY", date: utc("2026-11-26T14:00:00Z"), strokeCount: nil),
            // Too old for a 30-day window ending Nov 26 (starts Oct 28).
            ActivitySample(id: "6", typename: "VirtualRangeSessionActivity", kind: "VIRTUAL_RANGE", date: utc("2026-10-27T16:00:00Z"), strokeCount: 70),
        ]

        let days = Metrics.dailySwings(activities, endingAt: now, days: 30, calendar: calendar)

        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.first?.day, calendar.date(from: DateComponents(year: 2026, month: 10, day: 28)))
        XCTAssertEqual(days.last?.count, 5)
        XCTAssertEqual(days[28].count, 50)
        XCTAssertEqual(days[28].byKind, ["Virtual range": 40, "Simulator": 10])
        XCTAssertEqual(days.map(\.count).reduce(0, +), 55)
    }

    func testFullSwingFilter() {
        XCTAssertFalse(Metrics.isFullSwing(typename: "PerformancePuttingSessionActivity", kind: nil))
        XCTAssertFalse(Metrics.isFullSwing(typename: "SessionActivity", kind: "PUTTING"))
        XCTAssertTrue(Metrics.isFullSwing(typename: "VirtualRangeSessionActivity", kind: "VIRTUAL_RANGE"))
    }

    func testKindLabel() {
        XCTAssertEqual(Metrics.kindLabel("VIRTUAL_RANGE"), "Virtual range")
    }
}
