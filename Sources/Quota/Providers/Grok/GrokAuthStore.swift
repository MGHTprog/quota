import Foundation

/// Reads the access token written by `grok login` (`~/.grok/auth.json`).
struct GrokAuthStore {
    private struct Entry: Decodable {
        var key: String
    }

    private let fileManager: FileManager
    private let authFileURL: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.authFileURL = home.appendingPathComponent(".grok/auth.json")
    }

    /// Returns a Bearer token from `~/.grok/auth.json`.
    func loadAccessToken() throws -> String {
        guard fileManager.fileExists(atPath: authFileURL.path) else {
            throw GrokQuotaError.notSignedIn
        }

        let data: Data
        do {
            data = try Data(contentsOf: authFileURL)
        } catch {
            throw GrokQuotaError.notSignedIn
        }

        let entries: [String: Entry]
        do {
            entries = try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            throw GrokQuotaError.invalidResponse
        }

        guard let token = entries.values.map(\.key).first(where: { !$0.isEmpty }) else {
            throw GrokQuotaError.notSignedIn
        }
        return token
    }
}
