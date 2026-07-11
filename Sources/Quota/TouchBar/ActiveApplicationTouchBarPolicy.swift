import AppKit

struct ActiveApplicationInfo: Equatable {
    var bundleIdentifier: String?
    var localizedName: String?
}

struct ActiveApplicationTouchBarPolicy {
    private let allowedBundleIdentifiers: Set<String>
    private let allowedApplicationNames: Set<String>

    init(
        allowedBundleIdentifiers: Set<String> = [
            "com.openai.chat",
            "com.openai.codex",
            "com.apple.Terminal",
            "com.jetbrains.intellij",
            "com.jetbrains.intellij.ce"
        ],
        allowedApplicationNames: Set<String> = [
            "ChatGPT",
            "Codex",
            "IntelliJ IDEA",
            "IntelliJ IDEA CE"
        ]
    ) {
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
        self.allowedApplicationNames = allowedApplicationNames
    }

    func shouldShow(for application: ActiveApplicationInfo) -> Bool {
        if let bundleIdentifier = application.bundleIdentifier,
           allowedBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if let localizedName = application.localizedName,
           allowedApplicationNames.contains(localizedName) {
            return true
        }

        return false
    }
}
