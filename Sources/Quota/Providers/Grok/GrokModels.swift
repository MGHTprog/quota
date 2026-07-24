import Foundation

// MARK: - Wire types (Grok CLI billing API)
//
// Endpoint: GET https://cli-chat-proxy.grok.com/v1/billing?format=credits
// (same source the Grok CLI uses for `/usage`).
//
// Field semantics (from live responses + CLI billing logs):
// - `creditUsagePercent`: how much of the *weekly Build credit pool* has been
//   consumed (0...100). Protobuf JSON often **omits** this field when the
//   value is 0 — that means a full pool after reset, not "missing data".
// - `currentPeriod`: the active usage window (`USAGE_PERIOD_TYPE_WEEKLY`),
//   with `start` / `end`. `end` is the weekly reset time shown in the UI.
// - `billingPeriodStart` / `billingPeriodEnd`: on this credits endpoint they
//   usually mirror the weekly window; on the default (non-credits) billing
//   payload they can mean a calendar month. We only call `format=credits`,
//   and use `billingPeriodEnd` solely as a reset-time fallback.
// - `subscriptionTier`: plan label (envelope or config), e.g. "X Premium+".

/// Decoded payload of `GET .../v1/billing?format=credits`.
struct GrokBillingResponse: Decodable {
    var config: GrokBillingConfig
    /// Present on some response envelopes (CLI billing logs).
    var subscriptionTier: String?
}

struct GrokBillingConfig: Decodable {
    /// Weekly credit pool usage percent (0 = full remaining).
    ///
    /// Always non-optional after decode: wire omission / null → `0`.
    var creditUsagePercent: Double
    /// Active usage window (weekly for Build credits).
    var currentPeriod: GrokUsagePeriod?
    /// Reset-time fallback when `currentPeriod.end` is absent.
    var billingPeriodEnd: Date?
    var productUsage: [GrokProductUsage]?
    var subscriptionTier: String?

    init(
        creditUsagePercent: Double = 0,
        currentPeriod: GrokUsagePeriod? = nil,
        billingPeriodEnd: Date? = nil,
        productUsage: [GrokProductUsage]? = nil,
        subscriptionTier: String? = nil
    ) {
        self.creditUsagePercent = creditUsagePercent
        self.currentPeriod = currentPeriod
        self.billingPeriodEnd = billingPeriodEnd
        self.productUsage = productUsage
        self.subscriptionTier = subscriptionTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Protobuf JSON elides default doubles; absent/null means 0% used.
        creditUsagePercent = try container.decodeIfPresent(Double.self, forKey: .creditUsagePercent) ?? 0
        currentPeriod = try container.decodeIfPresent(GrokUsagePeriod.self, forKey: .currentPeriod)
        billingPeriodEnd = try container.decodeIfPresent(Date.self, forKey: .billingPeriodEnd)
        productUsage = try container.decodeIfPresent([GrokProductUsage].self, forKey: .productUsage)
        subscriptionTier = try container.decodeIfPresent(String.self, forKey: .subscriptionTier)
    }

    private enum CodingKeys: String, CodingKey {
        case creditUsagePercent
        case currentPeriod
        case billingPeriodEnd
        case productUsage
        case subscriptionTier
    }
}

struct GrokUsagePeriod: Decodable {
    /// e.g. `USAGE_PERIOD_TYPE_WEEKLY`.
    var type: String?
    var start: Date?
    /// End of this usage window (= weekly reset instant for Build credits).
    var end: Date?

    init(type: String? = nil, start: Date? = nil, end: Date? = nil) {
        self.type = type
        self.start = start
        self.end = end
    }
}

struct GrokProductUsage: Decodable {
    var product: String?
}

extension GrokBillingResponse {
    /// Subscription tier for the plan pill (e.g. "X Premium+").
    ///
    /// Do not fall back to `productUsage.product` — that is a product id like
    /// `GrokBuild`, not a user-facing plan name.
    var displayPlan: String? {
        let raw = subscriptionTier ?? config.subscriptionTier
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// When the weekly pool resets.
    ///
    /// Prefer `currentPeriod.end` (usage window). `billingPeriodEnd` is only a
    /// fallback for older / partial credits payloads — never used to infer usage.
    var resetsAt: Date? {
        config.currentPeriod?.end ?? config.billingPeriodEnd
    }
}

enum GrokWindowID {
    static let weekly = "weekly"
}

// MARK: - JSON decoding

enum GrokBillingCoding {
    /// Shared decoder for the credits billing API (ISO-8601 dates w/ optional fractional seconds).
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: value) {
                return date
            }

            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            if let date = basic.date(from: value) {
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

// MARK: - Mapping -> ProviderQuotaState

extension GrokBillingResponse {
    /// Maps a successfully decoded credits payload into UI state.
    ///
    /// Non-throwing by design: a 200 + decodable body always yields a window.
    /// Usage comes only from `creditUsagePercent` (default 0). Period fields
    /// affect reset time only — never whether the pool is considered full.
    func makeProviderState(
        identity: ProviderIdentity,
        now: Date = Date()
    ) -> ProviderQuotaState {
        let usedPercent = config.creditUsagePercent.clamped(to: 0...100)
        let window = QuotaWindow(
            id: GrokWindowID.weekly,
            title: L.weeklyTitle,
            usedPercent: usedPercent,
            remainingPercent: (100 - usedPercent).clamped(to: 0...100),
            resetsAt: resetsAt,
            isAvailable: true
        )

        return ProviderQuotaState(
            providerID: .grok,
            identity: identity,
            windows: [window],
            badges: [],
            updatedAt: now,
            sourceLabel: "cli-billing"
        )
    }
}

// MARK: - Errors

enum GrokQuotaError: LocalizedError {
    case notSignedIn
    case unauthorized
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L.grokNotSignedIn
        case .unauthorized:
            return L.grokUnauthorized
        case .invalidResponse:
            return L.invalidResponse
        case .requestFailed(let statusCode):
            return L.grokRequestFailed(statusCode)
        }
    }
}

// MARK: - Private helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
