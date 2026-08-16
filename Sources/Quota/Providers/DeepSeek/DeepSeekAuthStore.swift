import Foundation
import Security

/// Reads the DeepSeek API key from environment, config file, or Keychain.
///
/// DeepSeek uses API key authentication. The key can be provided via:
/// 1. Environment variable `DEEPSEEK_API_KEY`
/// 2. Config file `~/.deepseek/api_key`
/// 3. A value entered in Quota Settings and stored in macOS Keychain
struct DeepSeekAuthStore {
    static let shared = DeepSeekAuthStore()

    static let keychainService = "Quota-DeepSeek-api-key"
    static let keychainAccount = "api.deepseek.com"

    private let fileManager: FileManager
    private let apiKeyFileURL: URL
    private let environment: [String: String]
    private let keychainReader: () -> String?
    private let keychainWriter: (String?) throws -> Void

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychainReader: (() -> String?)? = nil,
        keychainWriter: ((String?) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.apiKeyFileURL = home.appendingPathComponent(".deepseek/api_key")
        self.environment = environment
        self.keychainReader = keychainReader ?? Self.readKeychainAPIKey
        self.keychainWriter = keychainWriter ?? Self.writeKeychainAPIKey
    }

    /// Matches Windows precedence: environment, config file, then saved value.
    func loadAPIKey() throws -> String {
        if let apiKey = Self.normalizeAPIKey(environment["DEEPSEEK_API_KEY"]),
           !apiKey.isEmpty {
            return apiKey
        }

        if fileManager.fileExists(atPath: apiKeyFileURL.path),
           let data = try? Data(contentsOf: apiKeyFileURL),
           let rawValue = String(data: data, encoding: .utf8),
           let apiKey = Self.normalizeAPIKey(rawValue),
           !apiKey.isEmpty {
            return apiKey
        }

        if let apiKey = Self.normalizeAPIKey(keychainReader()), !apiKey.isEmpty {
            return apiKey
        }

        throw DeepSeekQuotaError.notSignedIn
    }

    func savedAPIKey() -> String {
        Self.normalizeAPIKey(keychainReader()) ?? ""
    }

    func saveAPIKey(_ value: String) throws {
        let normalized = Self.normalizeAPIKey(value)
        try keychainWriter(normalized?.isEmpty == false ? normalized : nil)
    }

    private static func normalizeAPIKey(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return value }

        let first = value.first
        let last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func readKeychainAPIKey() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychainAPIKey(_ apiKey: String?) throws {
        if let apiKey {
            let data = Data(apiKey.utf8)
            let updateStatus = SecItemUpdate(
                keychainQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )

            if updateStatus == errSecItemNotFound {
                var item = keychainQuery
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                    throw DeepSeekQuotaError.keychainWriteFailed
                }
            } else if updateStatus != errSecSuccess {
                throw DeepSeekQuotaError.keychainWriteFailed
            }
        } else {
            let status = SecItemDelete(keychainQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw DeepSeekQuotaError.keychainWriteFailed
            }
        }
    }

    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }
}
