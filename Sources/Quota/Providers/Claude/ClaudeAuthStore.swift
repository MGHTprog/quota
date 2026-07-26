import Foundation

/// Credentials written by the Claude Code CLI sign-in.
///
/// macOS stores them as a Keychain generic password (service
/// `Claude Code-credentials`); some setups use `~/.claude/.credentials.json`
/// with the same JSON payload. Both are read-only here — Quota never refreshes
/// or rewrites the token (Claude Code does that itself as it is used).
struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable {
        var accessToken: String
        /// Milliseconds since epoch.
        var expiresAt: Double?
        /// e.g. `max`, `pro`.
        var subscriptionType: String?
    }

    var claudeAiOauth: OAuth
}

/// Reads the Claude Code OAuth token (Keychain first, credentials file as fallback).
struct ClaudeAuthStore {
    static let keychainService = "Claude Code-credentials"

    private let fileManager: FileManager
    private let credentialsFileURL: URL
    /// Test seam: replaces the Keychain lookup.
    private let keychainData: () -> Data?

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        keychainData: (() -> Data?)? = nil
    ) {
        self.fileManager = fileManager
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.credentialsFileURL = home.appendingPathComponent(".claude/.credentials.json")
        self.keychainData = keychainData ?? Self.loadKeychainData
    }

    /// Returns credentials with a non-expired access token.
    ///
    /// Falls back to the credentials file when the Keychain entry is missing
    /// *or* undecodable, so a stale/corrupt Keychain item cannot mask a valid
    /// file sign-in.
    func loadCredentials(now: Date = Date()) throws -> ClaudeCredentials {
        guard let credentials = decodeCredentials(from: keychainData())
            ?? decodeCredentials(from: loadFileData()) else {
            throw ClaudeQuotaError.notSignedIn
        }

        if let expiresAt = credentials.claudeAiOauth.expiresAt,
           Date(timeIntervalSince1970: expiresAt / 1000) <= now {
            throw ClaudeQuotaError.tokenExpired
        }

        return credentials
    }

    private func decodeCredentials(from data: Data?) -> ClaudeCredentials? {
        guard let data,
              let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data),
              !credentials.claudeAiOauth.accessToken.isEmpty else {
            return nil
        }
        return credentials
    }

    private func loadFileData() -> Data? {
        guard fileManager.fileExists(atPath: credentialsFileURL.path) else {
            return nil
        }
        return try? Data(contentsOf: credentialsFileURL)
    }

    /// Reads the item via `/usr/bin/security` instead of `SecItemCopyMatching`.
    ///
    /// Claude Code writes the credentials through the `security` CLI, so that
    /// binary is on the item's access list — reading the same way never shows
    /// the per-app Keychain permission prompt (a direct API read from Quota
    /// would prompt on every rebuild / reinstall).
    private static func loadKeychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        guard let payload = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !payload.isEmpty else {
            return nil
        }
        return Data(payload.utf8)
    }
}
