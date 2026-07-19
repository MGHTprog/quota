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
    private var panel: KeyablePanel?
    private var closeEventMonitor: Any?
    private var keyEventMonitor: Any?
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
        contentView.onDismiss = { [weak self] in self?.closePanel() }
        contentView.onPreferredSizeChange = { [weak self] in
            self?.resizePanelToFitContent(reposition: true)
        }
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
        debugLog("[Quota] \(providerID.rawValue) refresh failed: \(error.localizedDescription)")
        // Keep last good data when available; otherwise the panel shows neutral "--" rows.
        // Do not surface raw network errors in the UI.
        if let lastState {
            render(state: lastState)
        } else {
            if providerID == service.primaryProviderID {
                updateStatusLabel(remainingLabels: [], displayName: service.displayName(for: providerID))
            }
            syncContentView()
        }
    }

    // MARK: - Rendering

    private func render(state: ProviderQuotaState) {
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
        resizePanelToFitContent(reposition: panel?.isVisible == true)
    }

    /// Keep the content view and hosting panel the same size.
    ///
    /// NSPanel origin is bottom-left, so after a height change we re-anchor
    /// under the status item; otherwise All ↔ single tab switches clip or leave gaps.
    private func resizePanelToFitContent(reposition: Bool) {
        let size = contentView.intrinsicContentSize
        if contentView.frame.size != size {
            contentView.setFrameSize(size)
        }

        guard let panel else { return }

        if panel.frame.size != size {
            panel.setContentSize(size)
        }

        if reposition, panel.isVisible, let button = statusItem.button {
            panel.setFrameOrigin(panelOrigin(for: panel, button: button))
        }
    }

    private func showPanel() {
        syncContentView()
        guard let button = statusItem.button else { return }

        let panel = panel ?? makePanel()
        self.panel = panel
        resizePanelToFitContent(reposition: false)
        panel.setFrameOrigin(panelOrigin(for: panel, button: button))
        // Become key so ⌘R / ⌘Q / ⌘, / Esc work while the popup is open.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(contentView)
        startCloseMonitor()
        startKeyEventMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopCloseMonitor()
        stopKeyEventMonitor()
    }

    private func makePanel() -> KeyablePanel {
        let size = contentView.intrinsicContentSize
        let panel = KeyablePanel(
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
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

    /// Local monitor so shortcuts work even when the panel does not become first responder.
    /// Also intercepts ⌘, which AppKit may treat as a preferences key equivalent.
    private func startKeyEventMonitor() {
        stopKeyEventMonitor()
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
            // Only keyDown carries the shortcut action.
            guard event.type == .keyDown else { return event }
            if self.contentView.handlePanelKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    private func stopKeyEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }
}

/// Borderless status-item panel that can still become key for shortcuts.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
