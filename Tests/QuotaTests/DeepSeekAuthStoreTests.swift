import Foundation
import Testing
@testable import Quota

@Test func deepSeekCredentialPrecedenceIsEnvironmentThenFileThenKeychain() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-deepseek-auth-\(UUID().uuidString)")
    let config = home.appendingPathComponent(".deepseek")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try Data("file-key".utf8).write(to: config.appendingPathComponent("api_key"))

    let environmentStore = DeepSeekAuthStore(
        homeDirectory: home,
        environment: ["DEEPSEEK_API_KEY": " env-key "],
        keychainReader: { "saved-key" },
        keychainWriter: { _ in }
    )
    #expect(try environmentStore.loadAPIKey() == "env-key")

    let fileStore = DeepSeekAuthStore(
        homeDirectory: home,
        environment: [:],
        keychainReader: { "saved-key" },
        keychainWriter: { _ in }
    )
    #expect(try fileStore.loadAPIKey() == "file-key")

    try FileManager.default.removeItem(at: config.appendingPathComponent("api_key"))
    #expect(try fileStore.loadAPIKey() == "saved-key")
}

@Test func savesNormalizesAndDeletesDeepSeekAPIKey() throws {
    var writes: [String?] = []
    let store = DeepSeekAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: [:],
        keychainReader: { "saved-key" },
        keychainWriter: { writes.append($0) }
    )

    #expect(store.savedAPIKey() == "saved-key")
    try store.saveAPIKey("  \"sk-manual\"  ")
    try store.saveAPIKey(" ")

    #expect(writes.count == 2)
    #expect(writes[0] == "sk-manual")
    #expect(writes[1] == nil)
}

@Test func missingDeepSeekCredentialThrowsNotSignedIn() {
    let store = DeepSeekAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: [:],
        keychainReader: { nil },
        keychainWriter: { _ in }
    )

    #expect(throws: DeepSeekQuotaError.self) {
        _ = try store.loadAPIKey()
    }
}
