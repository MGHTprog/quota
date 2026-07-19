import AppKit
import Foundation
import UserNotifications

// MARK: - Threshold Definitions

/// Notification threshold levels ordered by severity.
private enum NotifyThreshold: Int, CaseIterable, Comparable {
    case warning = 0   // 20% — warning
    case urgent = 1    // 10% — urgent
    case critical = 2  //  5% — critical

    var percent: Double {
        switch self {
        case .warning:  return 20
        case .urgent:   return 10
        case .critical: return 5
        }
    }

    var emoji: String {
        switch self {
        case .warning:  return "🟡"
        case .urgent:   return "🔴"
        case .critical: return "🔴"
        }
    }

    var usesAlert: Bool {
        self == .urgent || self == .critical
    }

    static func < (lhs: NotifyThreshold, rhs: NotifyThreshold) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// System notification authorization state.
private enum NotificationAuthorizationState {
    case pending
    case authorized
    case denied
}

/// Notification held until authorization is granted (or delivered immediately when allowed).
private struct PendingNotification {
    var content: UNMutableNotificationContent
    var providerID: ProviderID
    /// Window id → newly crossed thresholds for this delivery.
    var crossedByWindow: [String: [NotifyThreshold]]
}

// MARK: - QuotaNotificationManager

/// Sends macOS notifications when remaining quota crosses severity thresholds.
///
/// - Thresholds: 20% (warning), 10% (urgent), 5% (critical).
/// - Each threshold fires once per `(provider, window)` until remaining rises above 50%.
/// - Titles/bodies are provider-agnostic (`ProviderQuotaState` only).
@MainActor
final class QuotaNotificationManager: QuotaServiceObserver {
    /// Whether the app is running inside a .app bundle required by UNUserNotificationCenter.
    private let available: Bool
    private let center: UNUserNotificationCenter?
    /// User notification authorization state; first-launch authorization is asynchronous.
    private var authorizationState: NotificationAuthorizationState = .pending
    private var pendingNotification: PendingNotification?
    private var hasPromptedEnableNotifications = false

    /// Highest notified threshold per provider → window id.
    private var notifiedByProvider: [ProviderID: [String: NotifyThreshold]] = [:]

    private let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    init() {
        let isBundle = Bundle.main.bundleURL.pathExtension == "app"
        if isBundle {
            self.available = true
            self.center = UNUserNotificationCenter.current()
            requestAuthorization()
        } else {
            self.available = false
            self.center = nil
            debugLog("[Quota] notifications: running without bundle, will log to stderr")
        }
    }

    // MARK: - QuotaServiceObserver

    func quotaService(_ service: QuotaService, didUpdate state: ProviderQuotaState) {
        debugLog("[Quota] notification manager received update for \(state.providerID.rawValue)")
        checkAndNotify(state: state)
    }

    func quotaService(
        _ service: QuotaService,
        didFail error: Error,
        providerID: ProviderID,
        lastState: ProviderQuotaState?
    ) {
        // Ignore failures here and wait for the next refresh.
    }

    // MARK: - Notification Logic

    private func checkAndNotify(state: ProviderQuotaState) {
        var notified = notifiedByProvider[state.providerID] ?? [:]
        var crossedByWindow: [String: [NotifyThreshold]] = [:]

        for window in state.windows where window.isAvailable {
            let remaining = window.remainingPercent
            // Above 50% remaining: treat as a fresh quota cycle and allow re-alerts later.
            if remaining > 50 {
                notified[window.id] = nil
            }

            let crossed = findNewCrossedThresholds(remaining: remaining, notified: notified[window.id])
            if !crossed.isEmpty {
                crossedByWindow[window.id] = crossed
            }
        }

        notifiedByProvider[state.providerID] = notified

        debugLog(
            "[Quota] checkAndNotify \(state.providerID.rawValue): windows=\(state.windows.map { "\($0.id)=\($0.isAvailable ? String(Int($0.remainingPercent)) : "--")" }), crossed=\(crossedByWindow.keys.sorted())"
        )

        guard !crossedByWindow.isEmpty else {
            debugLog("[Quota] no new thresholds crossed, skip notification")
            return
        }

        // One notification, focused on the single most urgent window (keeps title + body to two lines).
        guard let focus = mostUrgentCrossing(in: state, crossedByWindow: crossedByWindow) else {
            return
        }

        let content = buildNotificationContent(
            providerName: state.identity.displayName,
            window: focus.window,
            severity: focus.severity
        )
        let pending = PendingNotification(
            content: content,
            providerID: state.providerID,
            // Remember every window that crossed so we don't fire again for the quieter one.
            crossedByWindow: crossedByWindow
        )

        debugLog("[Quota] scheduling notification: title=\(content.title) focus=\(focus.window.id)")
        scheduleNotification(pending) { [weak self] delivered in
            guard let self, delivered else { return }
            self.markDelivered(pending)
        }
    }

    /// Finds newly crossed thresholds for a quota window.
    private func findNewCrossedThresholds(remaining: Double, notified: NotifyThreshold?) -> [NotifyThreshold] {
        NotifyThreshold.allCases.filter { threshold in
            remaining < threshold.percent && (notified == nil || threshold > notified!)
        }
    }

    /// Picks the window that needs attention most:
    /// 1) highest severity tier crossed, 2) lowest remaining %, 3) earlier in `state.windows`.
    private func mostUrgentCrossing(
        in state: ProviderQuotaState,
        crossedByWindow: [String: [NotifyThreshold]]
    ) -> (window: QuotaWindow, severity: NotifyThreshold)? {
        var best: (window: QuotaWindow, severity: NotifyThreshold)?

        for window in state.windows {
            guard let crossed = crossedByWindow[window.id], let severity = crossed.max() else {
                continue
            }
            guard let current = best else {
                best = (window, severity)
                continue
            }
            if severity > current.severity {
                best = (window, severity)
            } else if severity == current.severity,
                      window.remainingPercent < current.window.remainingPercent {
                best = (window, severity)
            }
        }

        return best
    }

    // MARK: - Notification Content

    private func buildNotificationContent(
        providerName: String,
        window: QuotaWindow,
        severity: NotifyThreshold
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let percent = Int(window.remainingPercent.rounded())

        content.title = L.lowQuotaTitle(
            providerName: providerName,
            windowTitle: window.localizedTitle,
            severity: severityLabel(severity)
        )

        if let resetsAt = window.resetsAt {
            resetFormatter.locale = L.locale
            let resetText = resetFormatter.string(from: resetsAt)
            content.body = L.lowQuotaBody(remainingPercent: percent, resetText: resetText)
        } else {
            content.body = L.lowQuotaBody(remainingPercent: percent)
        }

        if severity.usesAlert {
            content.sound = .default
        }

        return content
    }

    // MARK: - Helpers

    private func severityLabel(_ threshold: NotifyThreshold) -> String {
        switch threshold {
        case .warning:
            return L.severityWarning
        case .urgent:
            return L.severityUrgent
        case .critical:
            return L.severityCritical
        }
    }

    // MARK: - Delivery

    /// Delivers via the system notification center when allowed.
    ///
    /// Permission flow (same as typical macOS apps):
    /// - `.notDetermined` → system Allow / Don't Allow prompt (`requestAuthorization`)
    /// - `.authorized` → top-right banner via `UNUserNotificationCenter`
    /// - `.denied` → only then show a one-time alert guiding the user to System Settings
    ///   (macOS will not show the system permission sheet again after denial)
    private func scheduleNotification(
        _ pending: PendingNotification,
        completion: @escaping (Bool) -> Void
    ) {
        guard available, let center else {
            debugLog("[Quota] ── notification preview ──")
            debugLog("[Quota] title: \(pending.content.title)")
            debugLog("[Quota] body: \(pending.content.body)")
            debugLog("[Quota] ────────────")
            completion(true)
            return
        }

        // Always re-read system status so we never skip the system permission sheet
        // by relying on a stale in-memory state.
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }

                debugLog("[Quota] notification auth status: \(settings.authorizationStatus.rawValue)")

                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.authorizationState = .authorized
                    self.postToNotificationCenter(pending.content, completion: completion)

                case .notDetermined:
                    // System "Allow notifications?" prompt — not our custom center alert.
                    self.authorizationState = .pending
                    self.pendingNotification = pending
                    self.requestSystemAuthorization()
                    completion(false)

                case .denied:
                    self.authorizationState = .denied
                    // System will not re-prompt; guide user to Settings once.
                    self.promptOpenNotificationSettingsIfNeeded()
                    completion(false)

                @unknown default:
                    self.authorizationState = .denied
                    self.promptOpenNotificationSettingsIfNeeded()
                    completion(false)
                }
            }
        }
    }

    private func postToNotificationCenter(
        _ content: UNMutableNotificationContent,
        completion: @escaping (Bool) -> Void
    ) {
        guard let center else {
            completion(false)
            return
        }

        debugLog("[Quota] sending via UNUserNotificationCenter...")
        let request = UNNotificationRequest(
            identifier: "quota-low-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            Task { @MainActor in
                if let error {
                    debugLog("[Quota] notification delivery error: \(error.localizedDescription)")
                    completion(false)
                } else {
                    debugLog("[Quota] notification delivered successfully")
                    completion(true)
                }
            }
        }
    }

    private func deliverPendingNotificationIfNeeded() {
        guard let pending = pendingNotification else { return }

        pendingNotification = nil
        debugLog("[Quota] delivering deferred notification: title=\(pending.content.title)")
        scheduleNotification(pending) { [weak self] delivered in
            guard let self, delivered else { return }
            self.markDelivered(pending)
        }
    }

    private func markDelivered(_ pending: PendingNotification) {
        var notified = notifiedByProvider[pending.providerID] ?? [:]
        for (windowID, thresholds) in pending.crossedByWindow {
            if let highest = thresholds.max() {
                notified[windowID] = highest
            }
        }
        notifiedByProvider[pending.providerID] = notified
    }

    /// Called on launch to warm authorization (system prompt if still undetermined).
    private func requestAuthorization() {
        guard let center else { return }

        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }

                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.authorizationState = .authorized
                    self.deliverPendingNotificationIfNeeded()
                case .denied:
                    self.authorizationState = .denied
                case .notDetermined:
                    self.authorizationState = .pending
                    self.requestSystemAuthorization()
                @unknown default:
                    self.authorizationState = .denied
                }
            }
        }
    }

    /// Shows the standard system permission UI (Allow / Don't Allow).
    private func requestSystemAuthorization() {
        guard let center else { return }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    debugLog("[Quota] notification authorization error: \(error.localizedDescription)")
                }

                self.authorizationState = granted ? .authorized : .denied
                debugLog("[Quota] notification authorization: \(granted ? "granted" : "denied")")

                if granted {
                    self.deliverPendingNotificationIfNeeded()
                }
            }
        }
    }

    /// Only used after the user has already denied system permission.
    private func promptOpenNotificationSettingsIfNeeded() {
        guard !hasPromptedEnableNotifications else { return }
        hasPromptedEnableNotifications = true

        let alert = NSAlert()
        alert.messageText = L.notificationPermissionTitle
        alert.informativeText = L.notificationPermissionMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.openSystemSettings)
        alert.addButton(withTitle: L.later)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Prefer Notifications pane deep link when available.
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
