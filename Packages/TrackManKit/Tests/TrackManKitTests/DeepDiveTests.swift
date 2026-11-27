import XCTest
@testable import TrackManKit

final class AnalysisTests: XCTestCase {
    private func shot(_ session: String = "s1", day: Int = 1, club: String = "Driver", _ values: [ShotMetric: Double]) -> ShotRecord {
        ShotRecord(sessionID: session, date: utc("2026-11-\(String(format: "%02d", day))T12:00:00Z"), club: club, values: values)
    }

    func testDisplayConversion() {
        XCTAssertEqual(ShotMetric.clubSpeed.display(10), 10 * Units.mphPerMetersPerSecond, accuracy: 1e-9)
        XCTAssertEqual(ShotMetric.carry.display(100), 100 * Units.yardsPerMeter, accuracy: 1e-9)
        XCTAssertEqual(ShotMetric.impactOffset.display(0.012), 12, accuracy: 1e-9)
        XCTAssertEqual(ShotMetric.clubPath.display(-3.2), -3.2)
        XCTAssertEqual(ShotMetric.smashFactor.format(1.456), "1.46")
    }

    func testStatsAndPercentiles() throws {
        let shots = [1.0, 2, 3, 4, 5].map { shot([.clubPath: $0]) }
        let stats = try XCTUnwrap(Analysis.stats(shots, .clubPath))
        XCTAssertEqual(stats.count, 5)
        XCTAssertEqual(stats.mean, 3)
        XCTAssertEqual(stats.median, 3)
        XCTAssertEqual(stats.p10, 1.4, accuracy: 1e-9)
        XCTAssertEqual(stats.standardDeviation, 2.5.squareRoot(), accuracy: 1e-9)
        XCTAssertNil(Analysis.stats(shots, .faceAngle))
    }

    func testBySessionOrdersByDate() {
        let shots = [
            shot("late", day: 5, [.clubPath: 2]), shot("late", day: 5, [.clubPath: 4]),
            shot("early", day: 1, [.clubPath: -1]),
            shot("empty", day: 3, [.carry: 200]),
        ]
        let points = Analysis.bySession(shots, .clubPath)
        XCTAssertEqual(points.map(\.sessionID), ["early", "late"])
        XCTAssertEqual(points.last?.mean, 3)
    }

    func testRelationshipFindsPerfectLine() throws {
        let shots = (0..<5).map { i in shot([.faceToPath: Double(i), .spinAxis: 2 * Double(i) + 1]) }
        let r = Analysis.relationship(shots, x: .faceToPath, y: .spinAxis)
        XCTAssertEqual(try XCTUnwrap(r.slope), 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.intercept), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.correlation), 1, accuracy: 1e-9)
        XCTAssertNil(Analysis.relationship(Array(shots.prefix(2)), x: .faceToPath, y: .spinAxis).slope)
    }

    func testBucketsAndHistogram() {
        let shots = [-5.0, -1, 0, 1, 3, 6].map { shot([.clubPath: $0]) }
        let buckets = Analysis.buckets(shots, .clubPath, edges: [-2, 2], labels: ["Out", "Neutral", "In"])
        XCTAssertEqual(buckets.map(\.count), [1, 3, 2])
        XCTAssertEqual(buckets[1].share, 0.5)
        let bins = Analysis.histogram(shots, .clubPath, bins: 4)
        XCTAssertEqual(bins.map(\.count).reduce(0, +), 6)
        XCTAssertEqual(bins.first?.lower, -5)
        XCTAssertEqual(bins.last?.upper ?? 0, 6, accuracy: 1e-9)
    }
}

final class DeepDiveTests: XCTestCase {
    private func shots(_ count: Int, club: String = "Driver", make: (Int) -> [ShotMetric: Double]) -> [ShotRecord] {
        (0..<count).map { i in
            ShotRecord(sessionID: "s\(i % 2)", date: utc("2026-11-0\(1 + i % 2)T12:00:00Z"), club: club, values: make(i))
        }
    }

    func testPathReportFlagsOutToInAndOpenFace() {
        let data = shots(12) { i in [.clubPath: -4 + Double(i % 3) * 0.5, .faceAngle: 0, .faceToPath: 3.5] }
        let report = DeepDive.run(.path, shots: data, club: "Driver")
        XCTAssertEqual(report.shotCount, 12)
        XCTAssertEqual(report.sessionCount, 2)
        XCTAssertTrue(report.findings.contains { $0.contains("out-to-in") })
        XCTAssertTrue(report.findings.contains { $0.contains("open to the path") })
        XCTAssertTrue(report.missing.isEmpty)
        XCTAssertFalse(report.facts.isEmpty)
    }

    func testClubFilterAndTooFewShots() {
        let data = shots(10) { _ in [.clubPath: 1] } + shots(3, club: "7Iron") { _ in [.clubPath: 5] }
        let iron = DeepDive.run(.path, shots: data, club: "7Iron")
        XCTAssertEqual(iron.shotCount, 3)
        XCTAssertEqual(iron.findings.count, 1)
        XCTAssertTrue(iron.findings[0].hasPrefix("Only 3 shots"))
    }

    func testStrikeFallsBackToSmashWithoutImpactData() {
        let data = shots(10) { i in [.smashFactor: 1.40 + Double(i) * 0.01] }
        let report = DeepDive.run(.strike, shots: data, club: "Driver")
        XCTAssertEqual(report.missing, [.impactOffset, .impactHeight])
        XCTAssertTrue(report.findings.contains { $0.contains("no impact location") })
    }

    func testStrikeMapWithImpactData() {
        let data = shots(10) { i in [.impactOffset: Double(i - 5) / 1000, .impactHeight: 0.002, .smashFactor: 1.45] }
        let report = DeepDive.run(.strike, shots: data, club: "Driver")
        if case .strikeMap(_, let points) = report.charts.first {
            XCTAssertEqual(points.count, 10)
        } else {
            XCTFail("expected the strike map first")
        }
    }

    func testShapeCountsSlices() {
        let data = shots(10) { i in [.spinAxis: i < 4 ? 15 : 0, .faceToPath: i < 4 ? 6 : 0, .carrySide: 0] }
        let report = DeepDive.run(.shape, shots: data, club: "Driver")
        XCTAssertTrue(report.findings.contains { $0.hasPrefix("40% of shots slice") })
    }

    func testSpeedReport() {
        let data = shots(10) { i in [.clubSpeed: 40 + Double(i), .ballSpeed: 58 + Double(i), .smashFactor: 1.38, .carry: 180 + 3 * Double(i)] }
        let report = DeepDive.run(.speed, shots: data, club: "Driver")
        XCTAssertEqual(report.keyStats.first?.label, "Club speed")
        XCTAssertTrue(report.findings.contains { $0.contains("1.45 to 1.50") })
        XCTAssertTrue(report.findings.contains { $0.contains("more yards of carry") })
    }
}
