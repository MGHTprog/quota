import Foundation

/// Resolves the `codex` executable path used to start app-server.
struct CodexBinaryLocator {
    private let fileManager: FileManager
    private static let defaultBundledBinaryURLs = [
        // ChatGPT/Codex 0.133+ ship the CLI inside the `codex-cli` resource bundle.
        URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
        URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex-cli/bin/codex"),
        // Keep the legacy locations for older desktop-app releases.
        URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    ]
    private let bundledBinaryURLs: [URL]
    private let cliPathResolver: () -> URL?

    init(
        fileManager: FileManager = .default,
        bundledBinaryURLs: [URL] = Self.defaultBundledBinaryURLs,
        cliPathResolver: @escaping () -> URL? = CodexBinaryLocator.findCLI
    ) {
        self.fileManager = fileManager
        self.bundledBinaryURLs = bundledBinaryURLs
        self.cliPathResolver = cliPathResolver
    }

    /// Locates the codex binary by priority: CLI first, then ChatGPT.app, then legacy Codex.app.
    func locate() -> URL {
        if let cliPath = cliPathResolver() {
            debugLog("[Quota] found CLI codex at \(cliPath)")
            return cliPath
        }

        for binaryURL in bundledBinaryURLs where fileManager.isExecutableFile(atPath: binaryURL.path) {
            debugLog("[Quota] found bundled codex at \(binaryURL.path)")
            return binaryURL
        }

        debugLog("[Quota] no codex binary found")
        return bundledBinaryURLs[0]
    }

    /// Locates the CLI path through the which command.
    private static func findCLI() -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["codex"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: output)
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }
}
