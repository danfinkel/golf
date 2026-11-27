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
          netScore
          toPar
          outScore
          inScore
          courseHcp
          stat {
            driveAverage
            driveMax
            highestBallSpeed
            fairwayHitFairway
            fairwayHitLeft
            fairwayHitRight
            greenInRegulation
            numberOfPutts
            eagles
            birdies
            pars
            bogeys
            doubleBogeys
            tripleBogeysOrWorse
          }
          holes {
            holeNumber
            par
            strokeIndex
            distance
            grossScore
            putts
            greenInRegulation
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

    /// The player's current TrackMan handicap.
    public static let handicap = GraphQLOperation(name: "Handicap", query: """
    query Handicap {
      me {
        hcp { currentHcp }
      }
    }
    """)

    /// Every stroke of one practice session, by the activity's node id.
    public static let sessionStrokes = GraphQLOperation(name: "SessionStrokes", query: """
    query SessionStrokes($id: ID!) {
      node(id: $id) {
        __typename
        ... on SessionActivityInterface {
          strokes {
            time
            club
            measurement {
              clubSpeed
              ballSpeed
              smashFactor
              attackAngle
              clubPath
              faceAngle
              launchAngle
              spinRate
              carry
              total
              carrySide
              maxHeight
              faceToPath
              launchDirection
              spinAxis
              totalSide
            }
          }
        }
      }
    }
    """)
}
