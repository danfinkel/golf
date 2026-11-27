import Foundation

public enum APIError: Error, Equatable, LocalizedError {
    case http(status: Int, body: String)
    case graphQL([String])
    case emptyData

    public var errorDescription: String? {
        switch self {
        case .http(let status, _): return "TrackMan returned HTTP \(status)."
        case .graphQL(let messages): return "TrackMan error: \(messages.joined(separator: "; "))"
        case .emptyData: return "TrackMan returned no data."
        }
    }
}

public struct GraphQLOperation: Sendable {
    public let name: String
    public let query: String
}

/// Posts GraphQL operations to TrackMan with the bearer token. On a 401 it
/// refreshes the token once and retries.
public struct GraphQLClient: Sendable {
    let config: TrackManConfig
    let transport: HTTPTransport
    let tokens: TokenProvider

    public init(config: TrackManConfig = .portal, transport: HTTPTransport = URLSession.shared, tokens: TokenProvider) {
        self.config = config
        self.transport = transport
        self.tokens = tokens
    }

    public func execute<Response: Decodable>(_ operation: GraphQLOperation, variables: [String: any Sendable], as type: Response.Type) async throws -> Response {
        var token = try await tokens.validAccessToken()
        var (data, response) = try await transport.send(request(operation, variables: variables, token: token))
        if response.statusCode == 401 {
            token = try await tokens.validAccessToken(forceRefresh: true)
            (data, response) = try await transport.send(request(operation, variables: variables, token: token))
        }
        if response.statusCode == 401 { throw AuthError.reauthenticationRequired }
        guard response.statusCode == 200 else {
            throw APIError.http(status: response.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<Response>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw APIError.graphQL(errors.map(\.message))
        }
        guard let result = envelope.data else { throw APIError.emptyData }
        return result
    }

    func request(_ operation: GraphQLOperation, variables: [String: any Sendable], token: String) -> URLRequest {
        var components = URLComponents(url: config.graphQLURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fe_query", value: operation.name)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.webOrigin, forHTTPHeaderField: "Origin")
        request.setValue(config.webOrigin + "/", forHTTPHeaderField: "Referer")
        let body: [String: Any] = [
            "operationName": operation.name,
            "query": operation.query,
            "variables": variables as [String: Any],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

struct GraphQLEnvelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorMessage]?
}

struct GraphQLErrorMessage: Decodable {
    let message: String
}
