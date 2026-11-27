import Foundation

/// A course round (TrackMan scorecard). Distances are meters, as returned.
public struct Scorecard: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let createdAt: String?
    public let startedAt: String?
    public let course: Course?
    public let teeName: String?
    public let par: Int?
    public let numberOfHolesPlayed: Int?
    public let isCompleted: Bool?
    public let grossScore: Int?
    public let netScore: Int?
    public let toPar: Int?
    public let outScore: Int?
    public let inScore: Int?
    public let courseHcp: Double?
    public let stat: Stat?
    public let holes: [Hole]?

    /// One hole of the scorecard. Distance is meters.
    public struct Hole: Codable, Sendable, Equatable {
        public let holeNumber: Int?
        public let par: Int?
        public let strokeIndex: Int?
        public let distance: Double?
        public let grossScore: Int?
        public let putts: Int?
        public let greenInRegulation: Bool?

        public init(holeNumber: Int?, par: Int?, strokeIndex: Int? = nil, distance: Double? = nil,
                    grossScore: Int?, putts: Int? = nil, greenInRegulation: Bool? = nil) {
            self.holeNumber = holeNumber
            self.par = par
            self.strokeIndex = strokeIndex
            self.distance = distance
            self.grossScore = grossScore
            self.putts = putts
            self.greenInRegulation = greenInRegulation
        }
    }

    public struct Course: Decodable, Sendable, Equatable {
        public let displayName: String?
    }

    public struct Stat: Decodable, Sendable, Equatable {
        public let driveAverage: Double?
        public let driveMax: Double?
        /// Meters per second.
        public let highestBallSpeed: Double?
        /// Tee shots that finished in the fairway, left of it, or right of it.
        public let fairwayHitFairway: Int?
        public let fairwayHitLeft: Int?
        public let fairwayHitRight: Int?
        public let greenInRegulation: Int?
        public let numberOfPutts: Int?
        public let eagles: Int?
        public let birdies: Int?
        public let pars: Int?
        public let bogeys: Int?
        public let doubleBogeys: Int?
        public let tripleBogeysOrWorse: Int?
    }

    public var date: Date? { TrackManDate.parse(startedAt) ?? TrackManDate.parse(createdAt) }
}

/// A practice or play activity. Only sessions with shots carry strokeCount.
public struct Activity: Decodable, Sendable, Identifiable, Equatable {
    public let typename: String
    public let id: String
    public let kind: String?
    public let time: String?
    public let strokeCount: Int?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id, kind, time, strokeCount
    }

    public init(typename: String, id: String, kind: String?, time: String?, strokeCount: Int?) {
        self.typename = typename
        self.id = id
        self.kind = kind
        self.time = time
        self.strokeCount = strokeCount
    }

    public var date: Date? { TrackManDate.parse(time) }
}

public struct ActivityPage: Decodable, Sendable {
    public let totalCount: Int?
    public let pageInfo: PageInfo?
    public let items: [Activity]

    public struct PageInfo: Decodable, Sendable {
        public let hasNextPage: Bool?
    }
}

/// One shot from a practice session. Speeds are m/s, distances meters,
/// angles degrees, spin rpm, as TrackMan returns them.
public struct Stroke: Decodable, Sendable, Equatable {
    public let time: String?
    public let club: String?
    public let measurement: Measurement?

    public struct Measurement: Decodable, Sendable, Equatable {
        public let clubSpeed: Double?
        public let ballSpeed: Double?
        public let smashFactor: Double?
        public let attackAngle: Double?
        public let clubPath: Double?
        public let faceAngle: Double?
        public let launchAngle: Double?
        public let spinRate: Double?
        public let carry: Double?
        public let total: Double?
        public let carrySide: Double?
        public let maxHeight: Double?
        public let faceToPath: Double?
        public let launchDirection: Double?
        public let spinAxis: Double?
        public let totalSide: Double?
        // Requested only once the schema confirms them; nil until then.
        public let dynamicLoft: Double?
        public let curve: Double?
        public let impactOffset: Double?
        public let impactHeight: Double?
    }

    public var date: Date? { TrackManDate.parse(time) }
}

struct HandicapResponse: Decodable {
    let me: Me
    struct Me: Decodable { let hcp: Hcp? }
    struct Hcp: Decodable { let currentHcp: Double? }
}

struct SessionStrokesResponse: Decodable {
    let node: Node?
    struct Node: Decodable { let strokes: [Stroke]? }
}

struct CourseRoundsResponse: Decodable {
    let me: Me
    struct Me: Decodable { let scorecards: ScorecardList }
}

/// The POC handled `scorecards` as either a list or an `{ items }` page, so
/// both shapes are accepted here too.
struct ScorecardList: Decodable {
    let items: [Scorecard]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([Scorecard].self) {
            items = list
        } else {
            items = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([Scorecard].self, forKey: .items) ?? []
        }
    }
}

struct ActivitiesResponse: Decodable {
    let me: Me
    struct Me: Decodable { let activities: ActivityPage }
}

/// Typed access to the TrackMan queries the app uses.
public struct TrackManAPI: Sendable {
    let client: GraphQLClient

    public init(client: GraphQLClient) { self.client = client }

    public func scorecards(skip: Int, take: Int) async throws -> [Scorecard] {
        try await client.execute(Queries.courseRounds, variables: ["skip": skip, "take": take], as: CourseRoundsResponse.self)
            .me.scorecards.items
    }

    public func activities(skip: Int, take: Int) async throws -> [Activity] {
        try await client.execute(Queries.activities, variables: ["skip": skip, "take": take], as: ActivitiesResponse.self)
            .me.activities.items
    }

    /// The player's TrackMan handicap, or nil if none is set.
    public func handicap() async throws -> Double? {
        try await client.execute(Queries.handicap, variables: [:], as: HandicapResponse.self).me.hcp?.currentHcp
    }

    /// The shots of one practice session; empty for activities without shots.
    public func strokes(activityID: String) async throws -> [Stroke] {
        try await client.execute(Queries.sessionStrokes, variables: ["id": activityID], as: SessionStrokesResponse.self)
            .node?.strokes ?? []
    }
}
