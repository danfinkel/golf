import XCTest
@testable import TrackManKit

final class RoundMetricsTests: XCTestCase {
    func testFinishedRounds() {
        XCTAssertTrue(RoundMetrics.isFinished(isCompleted: true, holesPlayed: 4))
        XCTAssertTrue(RoundMetrics.isFinished(isCompleted: false, holesPlayed: 18))
        XCTAssertTrue(RoundMetrics.isFinished(isCompleted: nil, holesPlayed: 9))
        XCTAssertFalse(RoundMetrics.isFinished(isCompleted: false, holesPlayed: 4))
        XCTAssertFalse(RoundMetrics.isFinished(isCompleted: nil, holesPlayed: nil))
        XCTAssertFalse(RoundMetrics.isFinished(isCompleted: nil, holesPlayed: 12))
    }

    func testToParLabel() {
        XCTAssertEqual(RoundMetrics.toParLabel(0), "E")
        XCTAssertEqual(RoundMetrics.toParLabel(5), "+5")
        XCTAssertEqual(RoundMetrics.toParLabel(-2), "-2")
    }

    func testHoleResults() {
        XCTAssertEqual(RoundMetrics.result(score: 3, par: 5), .eagleOrBetter)
        XCTAssertEqual(RoundMetrics.result(score: 3, par: 4), .birdie)
        XCTAssertEqual(RoundMetrics.result(score: 4, par: 4), .par)
        XCTAssertEqual(RoundMetrics.result(score: 5, par: 4), .bogey)
        XCTAssertEqual(RoundMetrics.result(score: 8, par: 4), .doubleOrWorse)
        XCTAssertNil(RoundMetrics.result(score: nil, par: 4))
        XCTAssertNil(RoundMetrics.result(score: 0, par: 4))
    }

    func testNinesAndTotals() {
        let holes = (1...18).reversed().map { Scorecard.Hole(holeNumber: $0, par: 4, grossScore: $0 == 3 ? nil : 5) }
        let nines = RoundMetrics.nines(holes)
        XCTAssertEqual(nines.count, 2)
        XCTAssertEqual(nines[0].map(\.holeNumber), (1...9).map { Optional($0) })
        XCTAssertEqual(RoundMetrics.total(nines[0], \.par), 36)
        XCTAssertEqual(RoundMetrics.total(nines[0], \.grossScore), 40)   // hole 3 has no score
        XCTAssertEqual(RoundMetrics.nines(Array(holes.suffix(9))).count, 1)
        XCTAssertNil(RoundMetrics.total([], \.par))
    }

    func testClubLinesAndLabels() throws {
        let day = utc("2026-11-20T15:00:00Z")
        let shots = [
            ShotSample(date: day, club: "7Iron", ballSpeed: 50, carry: 140),
            ShotSample(date: day, club: "7Iron", ballSpeed: 52, carry: 150),
            ShotSample(date: day, club: "Driver", ballSpeed: 65, carry: 210),
            ShotSample(date: day, club: "PitchingWedge", carry: nil),
        ]
        let lines = ClubMetrics.lines(shots)
        XCTAssertEqual(lines.map(\.club), ["Driver", "7Iron", "PitchingWedge"])
        XCTAssertEqual(lines[1].shots, 2)
        XCTAssertEqual(try XCTUnwrap(lines[1].carryYards), 145 * Units.yardsPerMeter, accuracy: 0.001)
        XCTAssertNil(lines[2].carryYards)
        XCTAssertEqual(ClubMetrics.label("7Iron"), "7 Iron")
        XCTAssertEqual(ClubMetrics.label("PitchingWedge"), "Pitching Wedge")
        XCTAssertEqual(ClubMetrics.label("Driver"), "Driver")
    }

    func testScorecardHolesDecode() throws {
        let json = #"{"id":"r1","outScore":40,"inScore":42,"stat":{"birdies":1,"bogeys":6},"holes":[{"holeNumber":1,"par":4,"strokeIndex":17,"distance":259.0,"grossScore":5,"putts":2,"greenInRegulation":false}]}"#
        let card = try JSONDecoder().decode(Scorecard.self, from: Data(json.utf8))
        XCTAssertEqual(card.outScore, 40)
        XCTAssertEqual(card.stat?.birdies, 1)
        XCTAssertEqual(card.holes?.first?.grossScore, 5)
        XCTAssertEqual(card.holes?.first?.greenInRegulation, false)
        let roundTrip = try JSONDecoder().decode([Scorecard.Hole].self, from: JSONEncoder().encode(card.holes))
        XCTAssertEqual(roundTrip, card.holes)
    }
}
