import Foundation

/// Reads the DeepSeek API key from environment variables or config file.
///
/// DeepSeek uses API key authentication. The key can be provided via:
/// 1. Environment variable `DEEPSEEK_API_KEY`
/// 2. Config file `~/.deepseek/api_key`
struct DeepSeekAuthStore {
    private let fileManager: FileManager
    private let apiKeyFileURL: URL
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.apiKeyFileURL = home.appendingPathComponent(".deepseek/api_key")
        self.environment = environment
    }

    /// Returns the API key from environment variable or config file.
    func loadAPIKey() throws -> String {
        // Try environment variable first
        if let envKey = environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Try config file
        guard fileManager.fileExists(atPath: apiKeyFileURL.path) else {
            throw DeepSeekQuotaError.notSignedIn
        }

        let data: Data
        do {
            data = try Data(contentsOf: apiKeyFileURL)
        } catch {
            throw DeepSeekQuotaError.notSignedIn
        }

        guard let apiKey = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty else {
            throw DeepSeekQuotaError.notSignedIn
        }

        return apiKey
    }
}
