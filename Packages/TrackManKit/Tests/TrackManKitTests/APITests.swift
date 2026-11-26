import XCTest
@testable import TrackManKit

final class APITests: XCTestCase {
    private func makeAPI(_ responses: [(Int, String)], tokens: TokenSet) -> (TrackManAPI, StubTransport) {
        let transport = StubTransport(responses)
        let now = Date(timeIntervalSince1970: 0)
        let cookie = HTTPCookie(properties: [.domain: "portal.trackmangolf.com", .path: "/", .name: "s", .value: "1"])!
        let refresher = PortalSessionClient(transport: transport, cookies: { [cookie] }, now: { now })
        let provider = TokenProvider(refresher: refresher, store: InMemoryTokenStore(tokens), now: { now })
        return (TrackManAPI(client: GraphQLClient(transport: transport, tokens: provider)), transport)
    }

    private let valid = TokenSet(accessToken: "AT", expiresAt: .distantFuture)

    func testScorecardsDecodeFromListShape() async throws {
        let json = #"{"data":{"me":{"scorecards":[{"id":"r1","startedAt":"2026-11-23T11:26:56.6687807Z","course":{"displayName":"Bay Harbor"},"numberOfHolesPlayed":9,"isCompleted":true,"stat":{"driveAverage":182.1,"driveMax":192.5}}]}}}"#
        let (api, transport) = makeAPI([(200, json)], tokens: valid)

        let rounds = try await api.scorecards(skip: 0, take: 50)

        XCTAssertEqual(rounds.count, 1)
        XCTAssertEqual(rounds[0].course?.displayName, "Bay Harbor")
        XCTAssertEqual(rounds[0].stat?.driveAverage, 182.1)
        XCTAssertEqual(rounds[0].date, utc("2026-11-23T11:26:56.668Z"))

        let request = transport.recorded[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer AT")
        XCTAssertEqual(request.url?.query, "fe_query=CourseRounds")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["operationName"] as? String, "CourseRounds")
        XCTAssertEqual((body["variables"] as? [String: Int])?["take"], 50)
    }

    func testScorecardsDecodeFromItemsShape() async throws {
        let json = #"{"data":{"me":{"scorecards":{"items":[{"id":"r1"},{"id":"r2"}]}}}}"#
        let (api, _) = makeAPI([(200, json)], tokens: valid)
        let rounds = try await api.scorecards(skip: 0, take: 50)
        XCTAssertEqual(rounds.map(\.id), ["r1", "r2"])
    }

    func testActivitiesDecode() async throws {
        let json = #"{"data":{"me":{"activities":{"totalCount":2,"pageInfo":{"hasNextPage":false},"items":[{"__typename":"VirtualRangeSessionActivity","id":"a1","kind":"VIRTUAL_RANGE","time":"2026-11-17T12:48:31.5359259Z","strokeCount":67},{"__typename":"CoursePlayActivity","id":"a2","kind":"COURSE_PLAY","time":"2026-11-18T10:00:00Z"}]}}}}"#
        let (api, _) = makeAPI([(200, json)], tokens: valid)
        let items = try await api.activities(skip: 0, take: 50)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].strokeCount, 67)
        XCTAssertNil(items[1].strokeCount)
    }

    func test401RefreshesOnceAndRetries() async throws {
        let ok = #"{"data":{"me":{"scorecards":[]}}}"#
        let (api, transport) = makeAPI([
            (401, ""),
            (200, #"{"accessToken":"AT2","expires":3600,"isAuthenticated":true}"#),
            (200, ok),
        ], tokens: valid)

        _ = try await api.scorecards(skip: 0, take: 50)

        let sent = transport.recorded
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[1].url?.path, "/api/account/me")
        XCTAssertEqual(sent[2].value(forHTTPHeaderField: "Authorization"), "Bearer AT2")
    }

    func testGraphQLErrorsSurface() async {
        let (api, _) = makeAPI([(200, #"{"data":null,"errors":[{"message":"Not authorized"}]}"#)], tokens: valid)
        do {
            _ = try await api.scorecards(skip: 0, take: 50)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .graphQL(["Not authorized"]))
        }
    }

    func testDateParsingHandlesSevenDigitFractions() {
        XCTAssertEqual(TrackManDate.parse("2026-11-24T01:38:55.2193339Z"), TrackManDate.parse("2026-11-24T01:38:55.219Z"))
        XCTAssertNotNil(TrackManDate.parse("2026-11-24T01:38:55Z"))
        XCTAssertNotNil(TrackManDate.parse("2026-11-24T01:38:55.5"))
        XCTAssertNil(TrackManDate.parse(""))
        XCTAssertNil(TrackManDate.parse(nil))
    }

    func testPagingStopsAtKnownItem() async throws {
        struct Item: Identifiable { let id: String }
        var calls: [Int] = []
        let all = (0..<10).map { Item(id: "i\($0)") }
        let fetched = try await Paging.fetchNew(pageSize: 3, knownIDs: ["i4"], fullResync: false) { (skip: Int, take: Int) -> [Item] in
            calls.append(skip)
            return Array(all.dropFirst(skip).prefix(take))
        }
        XCTAssertEqual(calls, [0, 3])
        XCTAssertEqual(fetched.map(\.id), ["i0", "i1", "i2", "i3", "i4", "i5"])

        let everything = try await Paging.fetchNew(pageSize: 3, knownIDs: ["i4"], fullResync: true) { (skip: Int, take: Int) -> [Item] in
            Array(all.dropFirst(skip).prefix(take))
        }
        XCTAssertEqual(everything.count, 10)
    }
}
