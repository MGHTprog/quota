import Foundation

/// Shared JSON decoding for provider HTTP APIs (Grok billing, Claude usage).
enum QuotaJSONCoding {
    /// ISO-8601 with fractional seconds (e.g. `2026-07-26T14:20:00.015140+00:00`).
    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO-8601 without fractional seconds (e.g. `2026-07-26T14:20:00Z`).
    private static let basicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Decoder for ISO-8601 dates with optional fractional seconds.
    static func makeISO8601Decoder(convertFromSnakeCase: Bool = false) -> JSONDecoder {
        let decoder = JSONDecoder()
        if convertFromSnakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalSecondsFormatter.date(from: value)
                ?? basicFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }
}
