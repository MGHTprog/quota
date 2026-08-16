import Foundation

// MARK: - Wire types (DeepSeek balance API)
//
// Endpoint: GET https://api.deepseek.com/user/balance
//
// Field semantics (from API docs):
// - `is_available`: whether the user's balance is sufficient for API calls
// - `balance_infos`: array of balance information objects
//   - `currency`: currency code (CNY or USD)
//   - `total_balance`: total available balance (string-encoded decimal)
//   - `granted_balance`: granted/earned balance (string-encoded decimal)
//   - `topped_up_balance`: topped-up/paid balance (string-encoded decimal)

/// Decoded payload of `GET /user/balance`.
struct DeepSeekBalanceResponse: Decodable {
    var isAvailable: Bool
    var balanceInfos: [DeepSeekBalanceInfo]
}

struct DeepSeekBalanceInfo: Decodable {
    var currency: String
    var totalBalance: String
    var grantedBalance: String
    var toppedUpBalance: String
}

// MARK: - JSON decoding

enum DeepSeekBalanceCoding {
    /// Decoder for the balance API (snake_case keys).
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - Mapping -> ProviderQuotaState

extension DeepSeekBalanceResponse {
    /// Maps a successfully decoded balance payload into UI state.
    ///
    /// DeepSeek doesn't provide usage percentages like other providers.
    /// Instead, we show the balance information and availability status.
    func makeProviderState(
        identity: ProviderIdentity,
        now: Date = Date()
    ) -> ProviderQuotaState {
        let windows = makeWindows()
        
        return ProviderQuotaState(
            providerID: .deepseek,
            identity: identity,
            windows: windows,
            badges: makeBadges(),
            updatedAt: now,
            sourceLabel: "api-balance"
        )
    }
    
    private func makeWindows() -> [QuotaWindow] {
        guard let balanceInfo = balanceInfos.first else {
            return []
        }
        
        // Parse total balance
        guard let totalBalance = Double(balanceInfo.totalBalance) else {
            return []
        }
        
        // Calculate usage percentage (inverse of remaining)
        // Since DeepSeek only provides balance, we'll show it as a "remaining" window
        // We'll use a simple approach: show balance as a percentage of a reference amount
        // For now, we'll just show the balance amount and mark it as available
        
        let window = QuotaWindow(
            id: DeepSeekWindowID.balance,
            title: L.deepseekBalanceTitle,
            usedPercent: 0, // We don't have usage data
            remainingPercent: 100, // Show as full since we only have balance
            resetsAt: nil, // No reset time available
            isAvailable: isAvailable,
            scope: formatBalance(balanceInfo)
        )
        
        return [window]
    }
    
    private func makeBadges() -> [ProviderBadge] {
        guard let balanceInfo = balanceInfos.first else {
            return []
        }
        
        var badges: [ProviderBadge] = []
        
        // Add money badge with symbol
        let symbol = balanceInfo.currency == "CNY" ? "¥" : "$"
        if let total = Double(balanceInfo.totalBalance) {
            badges.append(.text("\(symbol)\(formatMoney(total))"))
        }
        
        // Add availability badge
        if !isAvailable {
            badges.append(.text(L.deepseekInsufficientBalance))
        }
        
        return badges
    }
    
    private func formatBalance(_ info: DeepSeekBalanceInfo) -> String {
        let symbol = info.currency == "CNY" ? "¥" : "$"
        
        guard let total = Double(info.totalBalance),
              let granted = Double(info.grantedBalance),
              let toppedUp = Double(info.toppedUpBalance) else {
            return "\(symbol)\(info.totalBalance)"
        }
        
        return "\(symbol)\(formatMoney(total)) (赠送: \(symbol)\(formatMoney(granted)), 充值: \(symbol)\(formatMoney(toppedUp)))"
    }
    
    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

enum DeepSeekWindowID {
    static let balance = "balance"
}

// MARK: - Errors

enum DeepSeekQuotaError: LocalizedError {
    case notSignedIn
    case unauthorized
    case invalidResponse
    case requestFailed(Int)
    case insufficientBalance

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L.deepseekNotSignedIn
        case .unauthorized:
            return L.deepseekUnauthorized
        case .invalidResponse:
            return L.invalidResponse
        case .requestFailed(let statusCode):
            return L.deepseekRequestFailed(statusCode)
        case .insufficientBalance:
            return L.deepseekInsufficientBalance
        }
    }
}
