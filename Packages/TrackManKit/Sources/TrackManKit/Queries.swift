import Foundation

/// Queries ported from the Python POC (trackman_scraper.py, course_play.py).
public enum Queries {
    public static let courseRounds = GraphQLOperation(name: "CourseRounds", query: """
    query CourseRounds($skip: Int, $take: Int) {
      me {
        scorecards(skip: $skip, take: $take) {
          id
          createdAt
          startedAt
          course { displayName }
          teeName
          par
          numberOfHolesPlayed
          isCompleted
          grossScore
          toPar
          stat {
            driveAverage
            driveMax
          }
        }
      }
    }
    """)

    public static let activities = GraphQLOperation(name: "Activities", query: """
    query Activities($skip: Int, $take: Int) {
      me {
        activities(skip: $skip, take: $take, includeHidden: false) {
          totalCount
          pageInfo { hasNextPage }
          items {
            __typename
            id
            kind
            time
            ... on SessionActivity { strokeCount }
            ... on VirtualRangeSessionActivity { strokeCount }
            ... on PerformancePuttingSessionActivity { strokeCount }
            ... on SimulatorSessionActivity { strokeCount }
            ... on ShotAnalysisSessionActivity { strokeCount }
            ... on TracySessionActivity { strokeCount }
            ... on MapMyBagSessionActivity { strokeCount }
          }
        }
      }
    }
    """)
}
