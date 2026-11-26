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
    public let toPar: Int?
    public let stat: Stat?

    public struct Course: Decodable, Sendable, Equatable {
        public let displayName: String?
    }

    public struct Stat: Decodable, Sendable, Equatable {
        public let driveAverage: Double?
        public let driveMax: Double?
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

/// Typed access to the two queries phase one needs.
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
}
