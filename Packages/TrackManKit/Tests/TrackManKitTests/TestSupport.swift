import Foundation
@testable import TrackManKit

/// Replays canned responses and records requests.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)]) {
        queue = responses.map { ($0.0, Data($0.1.utf8)) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: (Int, Data) = lock.withLock {
            requests.append(request)
            return queue.isEmpty ? (500, Data()) : queue.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: nil)!
        return (next.1, response)
    }

    var recorded: [URLRequest] { lock.withLock { requests } }
}

func formFields(_ request: URLRequest) -> [String: String] {
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    var fields: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        fields[parts[0]] = parts.count > 1 ? parts[1].removingPercentEncoding : ""
    }
    return fields
}

/// An unsigned JWT with the given payload, enough for claim decoding.
func fakeJWT(_ payload: String) -> String {
    func encode(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return encode(#"{"alg":"none"}"#) + "." + encode(payload) + ".sig"
}

func utc(_ string: String) -> Date { TrackManDate.parse(string)! }
