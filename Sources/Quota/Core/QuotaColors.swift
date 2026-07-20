import AppKit

// MARK: - Status semantics

/// Remaining-quota severity shared by menu bar, Touch Bar, and future surfaces.
///
/// Thresholds are defined once here so UI layers do not drift apart.
enum QuotaStatusStage: Equatable, Sendable {
    /// Remaining below the critical line (default: &lt; 20%).
    case critical
    /// Remaining in the warning band (default: 20%..<45%).
    case warning
    /// Healthy remaining (default: ≥ 45%).
    case healthy

    /// Maps a remaining-percent value into a stage.
    static func stage(forRemainingPercent percent: Double) -> QuotaStatusStage {
        let clamped = min(max(percent, 0), 100)
        switch clamped {
        case ..<QuotaStatusThresholds.critical:
            return .critical
        case ..<QuotaStatusThresholds.warning:
            return .warning
        default:
            return .healthy
        }
    }
}

/// Shared cutovers for remaining-percent coloring (percent left, not percent used).
enum QuotaStatusThresholds {
    /// Below this → critical (red).
    static let critical: Double = 20
    /// Below this (and ≥ critical) → warning (orange); otherwise healthy.
    static let warning: Double = 45
}

// MARK: - Rendering context

/// Where the color is painted — surfaces may differ in chroma/value for the same stage.
enum QuotaColorSurface: Equatable, Sendable {
    /// Menu-bar popover: small type + thin bars on vibrancy; prioritize contrast.
    case menuBar
    /// Touch Bar meters: distant, segment-based; prioritize punchy system colors.
    case touchBar
}

/// How the color is used within a surface.
enum QuotaColorRole: Equatable, Sendable {
    /// Digits / labels (need higher contrast on glass).
    case text
    /// Progress fill or Touch Bar segments (may be slightly brighter than text).
    case fill
}

// MARK: - Resolution

/// Semantic color tokens for quota UI.
///
/// Prefer this over ad-hoc RGB in views so thresholds and stage hues stay consistent.
enum QuotaColors {
    /// Color for a remaining-percent value on a given surface/role.
    static func status(
        remainingPercent: Double,
        surface: QuotaColorSurface,
        role: QuotaColorRole = .fill
    ) -> NSColor {
        status(
            QuotaStatusStage.stage(forRemainingPercent: remainingPercent),
            surface: surface,
            role: role
        )
    }

    /// Color for an already-classified stage.
    static func status(
        _ stage: QuotaStatusStage,
        surface: QuotaColorSurface,
        role: QuotaColorRole = .fill
    ) -> NSColor {
        switch surface {
        case .menuBar:
            return menuBarStatus(stage, role: role)
        case .touchBar:
            return touchBarStatus(stage)
        }
    }

    // MARK: Menu bar

    /// Custom calibrated colors: readable % text + slightly brighter bar on the same hue.
    private static func menuBarStatus(_ stage: QuotaStatusStage, role: QuotaColorRole) -> NSColor {
        let name = "Quota.status.menuBar.\(stage).\(role)"
        return NSColor(name: name) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return menuBarRGB(stage: stage, role: role, dark: dark)
        }
    }

    private static func menuBarRGB(
        stage: QuotaStatusStage,
        role: QuotaColorRole,
        dark: Bool
    ) -> NSColor {
        switch (stage, dark, role) {
        // Critical — red
        case (.critical, false, .text):
            return NSColor(calibratedRed: 0.78, green: 0.18, blue: 0.16, alpha: 1)
        case (.critical, false, .fill):
            return NSColor(calibratedRed: 0.84, green: 0.26, blue: 0.22, alpha: 0.95)
        case (.critical, true, .text):
            return NSColor(calibratedRed: 0.96, green: 0.48, blue: 0.44, alpha: 1)
        case (.critical, true, .fill):
            return NSColor(calibratedRed: 0.98, green: 0.54, blue: 0.50, alpha: 0.95)

        // Warning — orange
        case (.warning, false, .text):
            return NSColor(calibratedRed: 0.78, green: 0.42, blue: 0.08, alpha: 1)
        case (.warning, false, .fill):
            return NSColor(calibratedRed: 0.88, green: 0.52, blue: 0.14, alpha: 0.95)
        case (.warning, true, .text):
            return NSColor(calibratedRed: 0.96, green: 0.70, blue: 0.36, alpha: 1)
        case (.warning, true, .fill):
            return NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.42, alpha: 0.95)

        // Healthy — green (light: deep readable; dark: solid, less minty)
        case (.healthy, false, .text):
            return NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.24, alpha: 1)
        case (.healthy, false, .fill):
            return NSColor(calibratedRed: 0.12, green: 0.54, blue: 0.30, alpha: 0.95)
        case (.healthy, true, .text):
            return NSColor(calibratedRed: 0.42, green: 0.82, blue: 0.54, alpha: 1)
        case (.healthy, true, .fill):
            return NSColor(calibratedRed: 0.48, green: 0.86, blue: 0.58, alpha: 0.95)
        }
    }

    // MARK: Touch Bar

    /// System status colors — punchy on the black Touch Bar strip; no custom RGB.
    private static func touchBarStatus(_ stage: QuotaStatusStage) -> NSColor {
        switch stage {
        case .critical:
            return .systemRed
        case .warning:
            return .systemOrange
        case .healthy:
            return .systemGreen
        }
    }
}
