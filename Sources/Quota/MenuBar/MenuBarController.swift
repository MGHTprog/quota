import AppKit

/// Menu bar status item: compact quota popover, refresh/settings/quit actions.
///
/// Renders only `QuotaService.primaryProviderID` while the UI remains single-slot.
@MainActor
final class MenuBarController: NSObject, QuotaServiceObserver {
    private let service: QuotaService
    private let showSettings: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contentView = MenuBarLimitView(
        frame: NSRect(x: 0, y: 0, width: MenuBarLimitView.preferredSize.width, height: MenuBarLimitView.preferredSize.height)
    )
    private let errorItem = NSMenuItem()
    private let settingsItem = NSMenuItem()
    private let refreshItem = NSMenuItem()
    private let quitItem = NSMenuItem()
    private var usesIconOnly = false

    init(service: QuotaService, showSettings: @escaping () -> Void) {
        self.service = service
        self.showSettings = showSettings
    }

    func start() {
        if let image = loadStatusImage() {
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
            usesIconOnly = true
        } else {
            statusItem.button?.title = service.primaryProvider?.displayName ?? ""
        }
        statusItem.button?.toolTip = L.quotaTooltip
        debugLog("[Quota] status item created")

        let menu = NSMenu()
        let visualItem = NSMenuItem()
        visualItem.view = contentView
        visualItem.isEnabled = false

        errorItem.isEnabled = false
        errorItem.isHidden = true

        menu.addItem(visualItem)
        menu.addItem(errorItem)
        menu.addItem(.separator())
        settingsItem.action = #selector(openSettings)
        settingsItem.keyEquivalent = ","
        refreshItem.action = #selector(refresh)
        refreshItem.keyEquivalent = "r"
        quitItem.action = #selector(quit)
        quitItem.keyEquivalent = "q"
        menu.addItem(settingsItem)
        menu.addItem(refreshItem)
        menu.addItem(quitItem)
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        reloadLocalizedText()

        service.addObserver(self)
    }

    func reloadLocalizedText() {
        statusItem.button?.toolTip = L.quotaTooltip
        settingsItem.title = L.settings
        refreshItem.title = L.refresh
        quitItem.title = L.quit
        contentView.reloadLocalizedText()
    }

    // MARK: - QuotaServiceObserver

    func quotaService(_ service: QuotaService, didUpdate state: ProviderQuotaState) {
        guard state.providerID == service.primaryProviderID else { return }
        render(state: state, error: nil)
    }

    func quotaService(
        _ service: QuotaService,
        didFail error: Error,
        providerID: ProviderID,
        lastState: ProviderQuotaState?
    ) {
        guard providerID == service.primaryProviderID else { return }

        if let lastState {
            render(state: lastState, error: error)
        } else {
            updateStatusLabel(remainingLabels: [], displayName: service.displayName(for: providerID))
            errorItem.title = "\(L.errorPrefix): \(error.localizedDescription)"
            errorItem.isHidden = false
        }
    }

    // MARK: - Rendering

    private func render(state: ProviderQuotaState, error: Error?) {
        let rows = state.windowsForCompactDisplay()
        // Keep one entry per row so a missing 5h window still shows as "--" (not dropped).
        let remainingLabels = rows.map { window -> String in
            window.isAvailable ? "\(Int(window.remainingPercent.rounded()))%" : "--%"
        }

        updateStatusLabel(remainingLabels: remainingLabels, displayName: state.identity.displayName)
        debugLog(
            "[Quota] status updated: \(state.providerID.rawValue) \(remainingLabels.joined(separator: "/"))"
        )

        contentView.update(with: state)

        if let error {
            debugLog("[Quota] refresh failed: \(error.localizedDescription)")
            errorItem.title = "\(L.refreshFailedPrefix): \(error.localizedDescription)"
            errorItem.isHidden = false
        } else {
            errorItem.isHidden = true
        }
    }

    @objc private func refresh() {
        service.refreshAll()
    }

    @objc private func openSettings() {
        showSettings()
    }

    /// Programmatically opens the status-item menu (global hotkey entry point).
    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func loadStatusImage() -> NSImage? {
        let imageURL = Bundle.main
            .url(forResource: "MenuBarIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")

        guard let image = imageURL.flatMap(NSImage.init(contentsOf:)) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func updateStatusLabel(remainingLabels: [String], displayName: String) {
        guard !usesIconOnly else { return }

        if remainingLabels.isEmpty {
            statusItem.button?.title = "\(displayName) --%"
        } else {
            statusItem.button?.title = "\(displayName) \(remainingLabels.joined(separator: " / "))"
        }
    }
}
