import Foundation

/// TrackMan timestamps use 7 fractional digits ("2026-11-24T01:38:55.2193339Z"),
/// which ISO8601DateFormatter rejects, so the fraction is trimmed to 3 digits.
public enum TrackManDate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ string: String?) -> Date? {
        guard var text = string?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }

        if let dot = text.firstIndex(of: ".") {
            let afterDot = text[text.index(after: dot)...]
            let digits = afterDot.prefix { $0.isASCII && $0.isNumber }
            let rest = afterDot.dropFirst(digits.count)
            let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            text = String(text[..<dot]) + "." + millis + rest
        }

        let hasZone = text.hasSuffix("Z") || text.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        if !hasZone { text += "Z" }

        return withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }
}
