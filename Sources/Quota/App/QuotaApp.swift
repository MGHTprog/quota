import AppKit

/// Process entry point. Runs as a menu-bar accessory app (no Dock icon).
@main
struct QuotaApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
