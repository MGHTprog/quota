import AppKit

/// Menu bar status item: provider-driven quota panel and status label.
@MainActor
final class MenuBarController: NSObject, QuotaServiceObserver {
    private let service: QuotaService
    private let showSettings: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contentView = MenuBarLimitView(
        frame: NSRect(x: 0, y: 0, width: MenuBarLimitView.preferredSize.width, height: MenuBarLimitView.preferredSize.height)
    )
    private var panel: NSPanel?
    private var closeEventMonitor: Any?
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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        debugLog("[Quota] status item created")

        contentView.setFrameSize(contentView.intrinsicContentSize)
        contentView.onSettings = { [weak self] in self?.openSettings() }
        contentView.onRefresh = { [weak self] in self?.refresh() }
        contentView.onQuit = { [weak self] in self?.quit() }
        reloadLocalizedText()

        service.addObserver(self)
    }

    func reloadLocalizedText() {
        statusItem.button?.toolTip = L.quotaTooltip
        contentView.reloadLocalizedText()
        syncContentView()
    }

    // MARK: - QuotaServiceObserver

    func quotaService(_ service: QuotaService, didUpdate state: ProviderQuotaState) {
        render(state: state)
    }

    func quotaService(
        _ service: QuotaService,
        didFail error: Error,
        providerID: ProviderID,
        lastState: ProviderQuotaState?
    ) {
        if let lastState {
            render(state: lastState, error: error)
        } else {
            if providerID == service.primaryProviderID {
                updateStatusLabel(remainingLabels: [], displayName: service.displayName(for: providerID))
            }
            contentView.updateFailure(error, providerID: providerID)
            resizeContentViewIfNeeded()
        }
    }

    // MARK: - Rendering

    private func render(state: ProviderQuotaState, error: Error? = nil) {
        let rows = state.windowsForCompactDisplay()
        // Keep one entry per row so a missing 5h window still shows as "--" (not dropped).
        let remainingLabels = rows.map { window -> String in
            window.isAvailable ? "\(Int(window.remainingPercent.rounded()))%" : "--%"
        }

        if state.providerID == service.primaryProviderID {
            updateStatusLabel(remainingLabels: remainingLabels, displayName: state.identity.displayName)
        }
        debugLog(
            "[Quota] status updated: \(state.providerID.rawValue) \(remainingLabels.joined(separator: "/"))"
        )

        syncContentView()

        if let error {
            debugLog("[Quota] refresh failed: \(error.localizedDescription)")
            contentView.updateFailure(error, providerID: state.providerID)
        }
    }

    @objc private func refresh() {
        service.refreshAll()
    }

    @objc private func openSettings() {
        closePanel()
        showSettings()
    }

    /// Programmatically opens the status-item panel (global hotkey entry point).
    func showMenu() {
        showPanel()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
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

    private func syncContentView() {
        contentView.update(
            providers: service.visibleProviderOptions,
            states: service.visibleStates
        )
        resizeContentViewIfNeeded()
    }

    private func resizeContentViewIfNeeded() {
        let size = contentView.intrinsicContentSize
        guard contentView.frame.size != size else { return }
        contentView.setFrameSize(size)
        panel?.setContentSize(size)
    }

    private func showPanel() {
        syncContentView()
        guard let button = statusItem.button else { return }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(contentView.intrinsicContentSize)
        panel.setFrameOrigin(panelOrigin(for: panel, button: button))
        panel.orderFrontRegardless()
        startCloseMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopCloseMonitor()
    }

    private func makePanel() -> NSPanel {
        let size = contentView.intrinsicContentSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func panelOrigin(for panel: NSPanel, button: NSStatusBarButton) -> NSPoint {
        guard let window = button.window,
              let screen = window.screen ?? NSScreen.main else {
            return .zero
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)
        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame
        let gap: CGFloat = 2

        let x = min(
            max(buttonRectOnScreen.midX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let y = buttonRectOnScreen.minY - panelSize.height - gap
        return NSPoint(x: x, y: max(y, visibleFrame.minY + 8))
    }

    private func startCloseMonitor() {
        stopCloseMonitor()
        closeEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePanel()
            }
        }
    }

    private func stopCloseMonitor() {
        if let closeEventMonitor {
            NSEvent.removeMonitor(closeEventMonitor)
            self.closeEventMonitor = nil
        }
    }
}
