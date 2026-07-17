import AppKit

/// Shows a system-modal Touch Bar quota strip when an allowed app is frontmost.
///
/// Observes the primary provider only (same single-slot policy as the menu bar).
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate, QuotaServiceObserver {
    private let service: QuotaService
    private let workspace: NSWorkspace
    private let presentationPolicy: ActiveApplicationTouchBarPolicy
    private let presenter: SystemModalTouchBarPresenter
    private let contentView = TouchBarLimitView(frame: NSRect(x: 0, y: 0, width: 450, height: 26))
    private var activeApplicationObserver: NSObjectProtocol?
    private lazy var touchBar: NSTouchBar = {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.itemIdentifier]
        return touchBar
    }()
    private static let itemIdentifier = NSTouchBarItem.Identifier("app.quota.touchbar.item")
    private static let trayIdentifier = "app.quota.touchbar.tray"

    init(
        service: QuotaService,
        workspace: NSWorkspace = .shared,
        presentationPolicy: ActiveApplicationTouchBarPolicy = ActiveApplicationTouchBarPolicy(),
        presenter: SystemModalTouchBarPresenter? = nil
    ) {
        self.service = service
        self.workspace = workspace
        self.presentationPolicy = presentationPolicy
        self.presenter = presenter ?? SystemModalTouchBarPresenter(trayIdentifier: Self.trayIdentifier)
    }

    func start() {
        observeActiveApplication()
        updatePresentation(for: currentActiveApplication())
        service.addObserver(self)
    }

    func reloadLocalizedText() {
        contentView.reloadLocalizedText()
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.itemIdentifier else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = contentView
        item.customizationLabel = L.quotaTooltip
        return item
    }

    func quotaService(_ service: QuotaService, didUpdate state: ProviderQuotaState) {
        guard state.providerID == service.primaryProviderID else { return }
        contentView.update(with: state)
        debugLog("[Quota] Touch Bar updated")
        updatePresentation(for: currentActiveApplication())
    }

    func quotaService(
        _ service: QuotaService,
        didFail error: Error,
        providerID: ProviderID,
        lastState: ProviderQuotaState?
    ) {
        guard providerID == service.primaryProviderID else { return }
        if let lastState {
            contentView.update(with: lastState)
        }
        debugLog("[Quota] Touch Bar refresh failed: \(error.localizedDescription)")
        updatePresentation(for: currentActiveApplication())
    }

    private func observeActiveApplication() {
        guard activeApplicationObserver == nil else { return }

        activeApplicationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let application = ActiveApplicationInfo(
                bundleIdentifier: runningApplication?.bundleIdentifier,
                localizedName: runningApplication?.localizedName
            )

            Task { @MainActor [weak self] in
                self?.updatePresentation(for: application)
            }
        }
    }

    private func currentActiveApplication() -> ActiveApplicationInfo {
        let runningApplication = workspace.frontmostApplication
        return ActiveApplicationInfo(
            bundleIdentifier: runningApplication?.bundleIdentifier,
            localizedName: runningApplication?.localizedName
        )
    }

    private func updatePresentation(for application: ActiveApplicationInfo) {
        if presentationPolicy.shouldShow(for: application) {
            presenter.present(touchBar)
        } else {
            presenter.dismiss(touchBar)
        }
    }
}
