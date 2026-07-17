import AppKit

/// Custom-drawn two-row quota card shown inside the menu bar popover.
final class MenuBarLimitView: NSView {
    private enum Layout {
        static let width: CGFloat = 260
        static let height: CGFloat = 105
        static let padding: CGFloat = 14
        static let headerYFromTop: CGFloat = 20
        static let firstRowYFromTop: CGFloat = 44
        static let secondRowYFromTop: CGFloat = 86
        static let barHeight: CGFloat = 4
        static let lowThreshold: Double = 20
        static let midThreshold: Double = 45
    }

    static var preferredSize: NSSize {
        NSSize(width: Layout.width, height: Layout.height)
    }

    private var displayName = ""
    private var plan = ""
    private var badges: [ProviderBadge] = []
    /// Filled by `update(with:)`; empty rows until the first successful snapshot.
    private var rows: [QuotaWindow] = [.empty, .empty]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        Self.preferredSize
    }

    func update(with state: ProviderQuotaState) {
        displayName = state.identity.displayName
        plan = state.identity.plan ?? ""
        rows = state.windowsForCompactDisplay()
        badges = state.badges
        needsDisplay = true
    }

    func reloadLocalizedText() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width
        let pad = Layout.padding
        let sectionYs: [CGFloat] = [
            bounds.height - Layout.firstRowYFromTop,
            bounds.height - Layout.secondRowYFromTop
        ]

        drawHeader(pad: pad, maxX: width - pad)

        for (index, window) in rows.prefix(sectionYs.count).enumerated() {
            drawSection(
                window,
                at: NSPoint(x: pad, y: sectionYs[index]),
                width: width - pad * 2
            )
        }
    }

    // MARK: - Drawing

    private func drawHeader(pad: CGFloat, maxX: CGFloat) {
        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let planAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.systemBlue
        ]

        let header = NSMutableAttributedString(string: displayName, attributes: headerAttr)
        if !plan.isEmpty {
            header.append(NSAttributedString(string: " \(plan)", attributes: planAttr))
        }

        let origin = NSPoint(x: pad, y: bounds.height - Layout.headerYFromTop)
        header.draw(at: origin)

        if let badge = badges.first {
            drawBadgeText(
                text: badge.text,
                after: header,
                at: origin,
                maxX: maxX
            )
        }
    }

    private func drawSection(_ data: QuotaWindow, at origin: NSPoint, width: CGFloat) {
        let barHeight = Layout.barHeight
        let barX = origin.x
        let barY = origin.y

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let remainAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let percentAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]

        let remainText = L.remaining
        let maxPercentText = "100%"
        let clamped = min(max(data.remainingPercent, 0), 100)
        let percentText = data.isAvailable ? "\(Int(clamped.rounded()))%" : "--%"
        let remainSize = (remainText as NSString).size(withAttributes: remainAttr)
        let maxPercentSize = (maxPercentText as NSString).size(withAttributes: percentAttr)

        let barGap: CGFloat = 10
        let textGap: CGFloat = 4
        let barWidth = max(0, width - barGap - remainSize.width - textGap - maxPercentSize.width)

        data.title.draw(at: NSPoint(x: barX, y: barY + 6), withAttributes: titleAttr)

        let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
        let background = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSColor.tertiaryLabelColor.setFill()
        background.fill()

        let fillWidth = data.isAvailable ? barWidth * (clamped / 100) : 0
        if fillWidth > 0 {
            let fillRect = NSRect(x: barX, y: barY, width: fillWidth, height: barHeight)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
            barColor(for: clamped).setFill()
            fill.fill()
        }

        let remainX = barX + barWidth + barGap
        remainText.draw(at: NSPoint(x: remainX, y: barY - 2), withAttributes: remainAttr)

        let percentX = remainX + remainSize.width + textGap
        percentText.draw(at: NSPoint(x: percentX, y: barY - 2), withAttributes: percentAttr)

        let resetAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let resetText = data.isAvailable ? data.resetText : "\(L.reset) --"
        resetText.draw(at: NSPoint(x: barX, y: barY - 16), withAttributes: resetAttr)
    }

    private func drawBadgeText(
        text: String,
        after header: NSAttributedString,
        at origin: NSPoint,
        maxX: CGFloat
    ) {
        let textAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.82)
        ]
        let textSize = (text as NSString).size(withAttributes: textAttr)
        let textX = origin.x + header.size().width + 8
        guard textX + textSize.width <= maxX else { return }

        text.draw(
            at: NSPoint(x: textX, y: origin.y + 1),
            withAttributes: textAttr
        )
    }

    private func barColor(for percent: Double) -> NSColor {
        switch percent {
        case ..<Layout.lowThreshold: return .systemRed
        case ..<Layout.midThreshold: return .systemOrange
        default: return .systemGreen
        }
    }
}
