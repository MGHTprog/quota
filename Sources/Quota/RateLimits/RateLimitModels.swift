import Foundation

struct RateLimitDisplayState: Equatable {
    var fiveHour: LimitWindowDisplay
    var weekly: LimitWindowDisplay
    var resetCreditsAvailable: Int?
    var updatedAt: Date
}

struct LimitWindowDisplay: Equatable {
    var kind: LimitWindowKind
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var isAvailable: Bool

    var title: String {
        switch kind {
        case .fiveHour:
            return L.fiveHourTitle
        case .weekly:
            return L.weeklyTitle
        }
    }

    var resetText: String {
        guard let resetsAt else {
            return "\(L.reset) --"
        }

        Self.resetFormatter.locale = L.locale
        return "\(L.reset) " + Self.resetFormatter.string(from: resetsAt)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    static func unavailable(kind: LimitWindowKind) -> LimitWindowDisplay {
        LimitWindowDisplay(
            kind: kind,
            usedPercent: 0,
            remainingPercent: 0,
            resetsAt: nil,
            isAvailable: false
        )
    }
}

enum LimitWindowKind: Equatable {
    case fiveHour
    case weekly
}

struct GetAccountRateLimitsResponse: Decodable {
    var rateLimits: RateLimitSnapshot
    var rateLimitResetCredits: RateLimitResetCredits?
}

struct AccountResponse: Decodable {
    var account: AccountInfo
}

struct AccountInfo: Decodable {
    var planType: String?
}

struct RateLimitSnapshot: Decodable {
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
}

struct RateLimitWindow: Decodable {
    var usedPercent: Double
    var windowDurationMins: Int?
    var resetsAt: TimeInterval?
}

struct RateLimitResetCredits: Decodable, Equatable {
    var availableCount: Int?
}

extension GetAccountRateLimitsResponse {
    func displayState(now: Date = Date()) throws -> RateLimitDisplayState {
        guard rateLimits.primary != nil || rateLimits.secondary != nil else {
            throw CodexQuotaError.missingRateLimitWindow
        }

        var fiveHour: RateLimitWindow?
        var weekly: RateLimitWindow?

        classify(rateLimits.primary, fallbackKind: .fiveHour, fiveHour: &fiveHour, weekly: &weekly)
        classify(rateLimits.secondary, fallbackKind: .weekly, fiveHour: &fiveHour, weekly: &weekly)

        return RateLimitDisplayState(
            fiveHour: fiveHour?.display(kind: .fiveHour) ?? .unavailable(kind: .fiveHour),
            weekly: weekly?.display(kind: .weekly) ?? .unavailable(kind: .weekly),
            resetCreditsAvailable: rateLimitResetCredits?.availableCount,
            updatedAt: now
        )
    }

    private func classify(
        _ window: RateLimitWindow?,
        fallbackKind: LimitWindowKind,
        fiveHour: inout RateLimitWindow?,
        weekly: inout RateLimitWindow?
    ) {
        guard let window else { return }

        let kind: LimitWindowKind
        if let duration = window.windowDurationMins {
            kind = duration > 24 * 60 ? .weekly : .fiveHour
        } else {
            // Preserve the legacy primary/secondary meaning only when duration metadata is absent.
            kind = fallbackKind
        }

        switch kind {
        case .fiveHour:
            if fiveHour == nil { fiveHour = window }
        case .weekly:
            if weekly == nil { weekly = window }
        }
    }
}

private extension RateLimitWindow {
    func display(kind: LimitWindowKind) -> LimitWindowDisplay {
        let used = usedPercent.clamped(to: 0...100)
        return LimitWindowDisplay(
            kind: kind,
            usedPercent: used,
            remainingPercent: (100 - used).clamped(to: 0...100),
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)),
            isAvailable: true
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum CodexQuotaError: LocalizedError {
    case codexBinaryMissing
    case missingRateLimitWindow
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .codexBinaryMissing:
            return L.codexBinaryMissing
        case .missingRateLimitWindow:
            return L.missingRateLimitWindow
        case .invalidResponse:
            return L.invalidResponse
        case .rpcError(let message):
            return message
        }
    }
}
