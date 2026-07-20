import AppKit

/// Provider-driven quota panel shown from the menu bar.
final class MenuBarLimitView: NSView {
    private enum Layout {
        static let width: CGFloat = 260
        /// Primary content leading edge (logo, progress bar, section rule).
        static let outerPadding: CGFloat = 14
        /// Segmented filter control (connected cells, not separate chips).
        static let tabHeight: CGFloat = 30
        static let tabSegmentWidth: CGFloat = 34
        static let tabIconSize: CGFloat = 16
        /// Squared selection (not a stadium/ellipse pill).
        static let tabSelectionInset: CGFloat = 2
        static let tabSelectionCorner: CGFloat = 7
        static let headerIconSize: CGFloat = 26
        static let headerGap: CGFloat = 8
        /// Window row icon column; title + reset share this text leading edge.
        static let rowIconSize: CGFloat = 12
        static let textInset: CGFloat = 20
        static let cardGap: CGFloat = 12
        static let cardBottomPadding: CGFloat = 2
        static let tabsToContent: CGFloat = 10
        static let contentToFooter: CGFloat = 6
        static let footerHeight: CGFloat = 30
        static let availableRowHeight: CGFloat = 40
        static let compactRowHeight: CGFloat = 22
        static let barHeight: CGFloat = 3

        static func rowHeight(for window: QuotaWindow) -> CGFloat {
            window.isAvailable ? availableRowHeight : compactRowHeight
        }

        static func cardHeight(windows: [QuotaWindow]) -> CGFloat {
            let rows = windows.reduce(CGFloat.zero) { $0 + rowHeight(for: $1) }
            let body = max(compactRowHeight, rows)
            return headerIconSize + headerGap + body + cardBottomPadding
        }
    }

    /// Colors that follow light / dark appearance.
    /// Surface chrome comes from NSVisualEffectView (.popover); this palette is ink / chips only.
    private enum Palette {
        static let stroke = NSColor(name: "Quota.stroke") { appearance in
            appearance.isDarkQuotaAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: 0.06)
                : NSColor(calibratedWhite: 0, alpha: 0.07)
        }

        static let hairline = NSColor(name: "Quota.hairline") { appearance in
            appearance.isDarkQuotaAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: 0.06)
                : NSColor(calibratedWhite: 0, alpha: 0.06)
        }

        static let sectionDivider = NSColor(name: "Quota.sectionDivider") { appearance in
            appearance.isDarkQuotaAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: 0.07)
                : NSColor(calibratedWhite: 0, alpha: 0.07)
        }

        static let track = NSColor(name: "Quota.track") { appearance in
            appearance.isDarkQuotaAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: 0.14)
                : NSColor(calibratedWhite: 0, alpha: 0.12)
        }

        /// Selected segment: quiet wash like plan/badge pills (not a solid white tile).
        static let selectedTab = NSColor(name: "Quota.selectedTab") { appearance in
            appearance.isDarkQuotaAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: 0.10)
                : NSColor(calibratedWhite: 0, alpha: 0.07)
        }

        /// Hairline between segments.
        static let tabDivider = NSColor(name: "Quota.tabDivider") { appearance in
            appearance.isDarkQuotaAppearance
                ? NSColor(calibratedWhite: 1.0, alpha: 0.12)
                : NSColor(calibratedWhite: 0, alpha: 0.12)
        }

        static let strongText = NSColor.labelColor
        static let secondaryText = NSColor.secondaryLabelColor
        static let mutedText = NSColor.tertiaryLabelColor

        /// Membership / plan label — neutral so green stays reserved for quota state.
        static let planPill = NSColor.secondaryLabelColor
    }

    static var preferredSize: NSSize {
        NSSize(width: Layout.width, height: 250)
    }

    var onSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onDismiss: (() -> Void)?
    /// Called when the panel should resize (e.g. switching All / single provider).
    var onPreferredSizeChange: (() -> Void)?

    private var iconCache: [String: NSImage] = [:]
    private var providerOptions: [ProviderSettingsOption] = []
    private var statesByProvider: [ProviderID: ProviderQuotaState] = [:]
    private var selectedProviderID: ProviderID?
    private var tabRects: [(id: ProviderID?, rect: NSRect)] = []
    private var footerRects: [(action: FooterAction, rect: NSRect)] = []

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Layout.width, height: calculatedHeight)
    }

    private var calculatedHeight: CGFloat {
        let visibleOptions = selectedOptions
        let cardHeights = visibleOptions.reduce(CGFloat.zero) { total, option in
            total + Layout.cardHeight(windows: displayWindows(for: option))
        }
        let gaps = max(0, visibleOptions.count - 1)
        return Layout.outerPadding
            + Layout.tabHeight
            + Layout.tabsToContent
            + cardHeights
            + CGFloat(gaps) * Layout.cardGap
            + Layout.contentToFooter
            + Layout.footerHeight
    }

    private var selectedOptions: [ProviderSettingsOption] {
        guard let selectedProviderID,
              let selected = providerOptions.first(where: { $0.id == selectedProviderID }) else {
            return providerOptions
        }
        return [selected]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func update(providers: [ProviderSettingsOption], states: [ProviderQuotaState]) {
        providerOptions = providers
        statesByProvider = Dictionary(uniqueKeysWithValues: states.map { ($0.providerID, $0) })

        if let selectedProviderID,
           !providers.contains(where: { $0.id == selectedProviderID }) {
            self.selectedProviderID = nil
        }

        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func reloadLocalizedText() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        tabRects.removeAll()
        footerRects.removeAll()

        drawBackground()
        drawTabs()
        drawCards()
        drawFooter()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let tab = tabRects.first(where: { $0.rect.contains(point) }) {
            guard selectedProviderID != tab.id else { return }
            selectedProviderID = tab.id
            invalidateIntrinsicContentSize()
            needsDisplay = true
            onPreferredSizeChange?()
            return
        }

        guard let footer = footerRects.first(where: { $0.rect.contains(point) }) else {
            return
        }

        switch footer.action {
        case .settings:
            onSettings?()
        case .refresh:
            onRefresh?()
        case .quit:
            onQuit?()
        }
    }

    /// Panel shortcuts: ⌘, settings · ⌘R refresh · ⌘Q quit · Esc dismiss.
    private enum PanelKeyCode {
        static let escape: UInt16 = 53
        static let r: UInt16 = 15
        static let q: UInt16 = 12
        static let comma: UInt16 = 43
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlePanelKeyEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handlePanelKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    @discardableResult
    func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == PanelKeyCode.escape {
            onDismiss?()
            return true
        }

        let commandOnly = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)
        guard commandOnly else { return false }

        switch event.keyCode {
        case PanelKeyCode.comma:
            onSettings?()
            return true
        case PanelKeyCode.r:
            onRefresh?()
            return true
        case PanelKeyCode.q:
            onQuit?()
            return true
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case ",":
                onSettings?()
                return true
            case "r":
                onRefresh?()
                return true
            case "q":
                onQuit?()
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Drawing

    private func drawBackground() {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        Palette.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTabs() {
        let segments = tabSegments()
        guard !segments.isEmpty else { return }

        let segmentWidth = tabSegmentWidth(count: segments.count)
        let trackWidth = segmentWidth * CGFloat(segments.count)
        let trackHeight = Layout.tabHeight
        let trackRect = NSRect(
            x: Layout.outerPadding,
            y: bounds.height - Layout.outerPadding - trackHeight,
            width: trackWidth,
            height: trackHeight
        )

        // No outer elliptical track — only a squared selection behind the active icon.
        if let selectedIndex = segments.firstIndex(where: { $0.id == selectedProviderID }) {
            let cell = segmentCellRect(track: trackRect, index: selectedIndex, width: segmentWidth)
            let highlight = cell.insetBy(dx: Layout.tabSelectionInset, dy: Layout.tabSelectionInset)
            let path = NSBezierPath(
                roundedRect: highlight,
                xRadius: Layout.tabSelectionCorner,
                yRadius: Layout.tabSelectionCorner
            )
            Palette.selectedTab.setFill()
            path.fill()
        }

        // Light dividers between icons (skip edges touching the selection).
        if segments.count > 1 {
            let selectedIndex = segments.firstIndex(where: { $0.id == selectedProviderID })
            for index in 1..<segments.count {
                let touchesSelection = selectedIndex == index || selectedIndex == index - 1
                if touchesSelection { continue }
                let x = trackRect.minX + CGFloat(index) * segmentWidth
                let insetY: CGFloat = 9
                Palette.tabDivider.setStroke()
                NSBezierPath.strokeLine(
                    from: NSPoint(x: x, y: trackRect.minY + insetY),
                    to: NSPoint(x: x, y: trackRect.maxY - insetY)
                )
            }
        }

        for (index, segment) in segments.enumerated() {
            let cell = segmentCellRect(track: trackRect, index: index, width: segmentWidth)
            tabRects.append((segment.id, cell))
            let iconSize = Layout.tabIconSize
            let iconRect = NSRect(
                x: cell.midX - iconSize / 2,
                y: cell.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            drawTabIcon(
                option: segment.option,
                rect: iconRect,
                isSelected: segment.id == selectedProviderID
            )
        }
    }

    private struct TabSegment {
        var id: ProviderID?
        var option: ProviderSettingsOption?
    }

    private func tabSegments() -> [TabSegment] {
        var segments: [TabSegment] = [TabSegment(id: nil, option: nil)]
        segments.append(contentsOf: providerOptions.map { TabSegment(id: $0.id, option: $0) })
        return segments
    }

    private func tabSegmentWidth(count: Int) -> CGFloat {
        guard count > 0 else { return Layout.tabSegmentWidth }
        let available = bounds.width - Layout.outerPadding * 2
        let natural = CGFloat(count) * Layout.tabSegmentWidth
        if natural <= available {
            return Layout.tabSegmentWidth
        }
        return max(28, floor(available / CGFloat(count)))
    }

    private func segmentCellRect(track: NSRect, index: Int, width: CGFloat) -> NSRect {
        NSRect(
            x: track.minX + CGFloat(index) * width,
            y: track.minY,
            width: width,
            height: track.height
        )
    }

    private func drawCards() {
        var y = bounds.height - Layout.outerPadding - Layout.tabHeight - Layout.tabsToContent
        for (index, option) in selectedOptions.enumerated() {
            let windows = displayWindows(for: option)
            let height = Layout.cardHeight(windows: windows)
            y -= height
            let rect = NSRect(
                x: Layout.outerPadding,
                y: y,
                width: bounds.width - Layout.outerPadding * 2,
                height: height
            )
            drawProviderCard(option: option, windows: windows, rect: rect)
            if index < selectedOptions.count - 1 {
                drawSectionSeparator(y: y - Layout.cardGap / 2)
            }
            y -= Layout.cardGap
        }
    }

    private func drawFooter() {
        let lineY = Layout.footerHeight + 1
        Palette.hairline.setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: Layout.outerPadding, y: lineY),
            to: NSPoint(x: bounds.width - Layout.outerPadding, y: lineY)
        )

        // Tool actions, not a tab bar: intrinsic-width chips, even gaps, no vertical rules.
        let actions: [(FooterAction, String, String?, FooterWeight)] = [
            (.settings, "gearshape", L.settings, .normal),
            (.refresh, "arrow.clockwise", L.refresh, .normal),
            (.quit, "power", L.quit, .quiet)
        ]

        let metrics: [(FooterAction, String, String?, FooterWeight, CGFloat)] = actions.map { item in
            let width = footerItemWidth(symbol: item.1, title: item.2)
            return (item.0, item.1, item.2, item.3, width)
        }
        let totalWidth = metrics.reduce(CGFloat.zero) { $0 + $1.4 }
        let gaps = CGFloat(max(0, metrics.count - 1))
        let available = bounds.width - Layout.outerPadding * 2
        let gap = metrics.count > 1 ? max(12, (available - totalWidth) / gaps) : 0
        var x = Layout.outerPadding + max(0, (available - totalWidth - gap * gaps) / 2)
        let itemHeight: CGFloat = 22
        let y: CGFloat = 4

        for item in metrics {
            let rect = NSRect(x: x, y: y, width: item.4, height: itemHeight)
            drawFooterButton(
                systemSymbol: item.1,
                title: item.2,
                weight: item.3,
                rect: rect
            )
            footerRects.append((item.0, rect.insetBy(dx: -4, dy: -2)))
            x += item.4 + gap
        }
    }

    private func footerItemWidth(symbol: String, title: String?) -> CGFloat {
        let icon: CGFloat = 12
        guard let title, !title.isEmpty else {
            return icon + 10
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular)
        ]
        let textWidth = (title as NSString).size(withAttributes: attributes).width
        return icon + 4 + textWidth + 8
    }

    private func drawProviderCard(option: ProviderSettingsOption, windows: [QuotaWindow], rect: NSRect) {
        let state = statesByProvider[option.id]
        let identity = state?.identity ?? ProviderIdentity(displayName: option.displayName, plan: nil)

        let headerY = rect.maxY - Layout.headerIconSize
        drawProviderIcon(option: option, rect: NSRect(
            x: rect.minX,
            y: headerY,
            width: Layout.headerIconSize,
            height: Layout.headerIconSize
        ))

        drawHeader(identity: identity, badges: state?.badges ?? [], rect: NSRect(
            x: rect.minX + Layout.headerIconSize + Layout.headerGap,
            y: headerY,
            width: rect.width - Layout.headerIconSize - Layout.headerGap,
            height: Layout.headerIconSize
        ))

        var y = headerY - Layout.headerGap
        for window in windows {
            let height = Layout.rowHeight(for: window)
            y -= height
            drawWindow(window, rect: NSRect(x: rect.minX, y: y, width: rect.width, height: height))
        }
    }

    private func drawHeader(identity: ProviderIdentity, badges: [ProviderBadge], rect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: Palette.strongText
        ]
        let title = identity.displayName
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        title.draw(
            at: NSPoint(x: rect.minX, y: rect.midY - titleSize.height / 2),
            withAttributes: titleAttributes
        )

        var x = rect.minX + titleSize.width + 7
        let dark = effectiveAppearance.isDarkQuotaAppearance
        let pillFill = dark ? 0.14 : 0.08

        // Plan / membership: small neutral pill (green reserved for remaining %).
        if let plan = identity.plan, !plan.isEmpty {
            x = drawPill(
                text: plan,
                x: x,
                centerY: rect.midY,
                color: Palette.planPill,
                backgroundAlpha: pillFill
            )
        }

        // Codex reset credits etc. — keep as quiet secondary pills (not green / not button-like).
        for badge in badges.prefix(2) {
            x = drawPill(
                text: badge.localizedText,
                x: x,
                centerY: rect.midY,
                color: Palette.secondaryText,
                backgroundAlpha: pillFill
            )
        }
    }

    private func drawWindow(_ window: QuotaWindow, rect: NSRect) {
        if !window.isAvailable {
            drawCompactUnavailableWindow(window, rect: rect)
            return
        }

        let clamped = min(max(window.remainingPercent, 0), 100)
        let percentText = "\(Int(clamped.rounded()))%"
        let percentTint = QuotaColors.status(
            remainingPercent: clamped,
            surface: .menuBar,
            role: .text
        )
        let barTint = QuotaColors.status(
            remainingPercent: clamped,
            surface: .menuBar,
            role: .fill
        )

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: Palette.strongText
        ]
        let percentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: percentTint
        ]
        let remainingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.secondaryText
        ]
        let resetAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.mutedText
        ]

        let titleX = rect.minX + Layout.textInset
        let titleY = rect.maxY - 16
        let rightY = titleY
        let resetY = rect.minY + 3

        let iconRect = NSRect(
            x: rect.minX,
            y: titleY + 1,
            width: Layout.rowIconSize,
            height: Layout.rowIconSize
        )
        drawWindowIcon(windowID: window.id, rect: iconRect)

        window.localizedTitle.draw(at: NSPoint(x: titleX, y: titleY), withAttributes: titleAttributes)

        let remainingSize = (L.remaining as NSString).size(withAttributes: remainingAttributes)
        let percentSize = (percentText as NSString).size(withAttributes: percentAttributes)
        let percentColumnWidth = ("100%" as NSString).size(withAttributes: percentAttributes).width
        let percentColumnX = rect.maxX - percentColumnWidth
        let remainingX = percentColumnX - 4 - remainingSize.width

        L.remaining.draw(at: NSPoint(x: remainingX, y: rightY), withAttributes: remainingAttributes)
        percentText.draw(
            at: NSPoint(x: percentColumnX + percentColumnWidth - percentSize.width, y: rightY),
            withAttributes: percentAttributes
        )

        // Progress shares primary leading edge with logo / section rules.
        let barRect = NSRect(
            x: rect.minX,
            y: rect.midY - 2,
            width: rect.width,
            height: Layout.barHeight
        )
        drawProgressBar(in: barRect, percent: clamped, color: barTint)

        // Reset aligns with title text (secondary leading edge).
        window.resetText.draw(at: NSPoint(x: titleX, y: resetY), withAttributes: resetAttributes)
    }

    /// Unavailable windows: one quiet line — no empty bar / “Reset --” noise.
    private func drawCompactUnavailableWindow(_ window: QuotaWindow, rect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: Palette.secondaryText
        ]
        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.mutedText
        ]

        let titleX = rect.minX + Layout.textInset
        let titleY = rect.midY - 7

        let iconRect = NSRect(
            x: rect.minX,
            y: rect.midY - Layout.rowIconSize / 2,
            width: Layout.rowIconSize,
            height: Layout.rowIconSize
        )
        drawWindowIcon(windowID: window.id, rect: iconRect, muted: true)

        window.localizedTitle.draw(at: NSPoint(x: titleX, y: titleY), withAttributes: titleAttributes)

        let status = L.noData
        let statusSize = (status as NSString).size(withAttributes: statusAttributes)
        status.draw(
            at: NSPoint(x: rect.maxX - statusSize.width, y: rect.midY - statusSize.height / 2),
            withAttributes: statusAttributes
        )
    }

    private func drawProgressBar(in rect: NSRect, percent: Double, color: NSColor) {
        let background = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        Palette.track.setFill()
        background.fill()

        let fillWidth = max(0, min(rect.width, rect.width * percent / 100))
        guard fillWidth > 0 else { return }

        let fill = NSBezierPath(
            roundedRect: NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height),
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
        color.setFill()
        fill.fill()
    }

    private func drawProviderIcon(option: ProviderSettingsOption, rect: NSRect) {
        if let icon = providerIcon(for: option) {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        accentColor(for: option).setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: option.fallbackGlyph.count > 1 ? 8 : 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (option.fallbackGlyph as NSString).size(withAttributes: attributes)
        option.fallbackGlyph.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private enum FooterWeight {
        case normal
        case quiet
    }

    private func drawFooterButton(
        systemSymbol: String,
        title: String?,
        weight: FooterWeight,
        rect: NSRect
    ) {
        let color: NSColor = {
            switch weight {
            case .normal:
                return Palette.secondaryText
            case .quiet:
                return Palette.mutedText
            }
        }()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: color
        ]
        let iconSize: CGFloat = 12
        let titleSize = title.map { ($0 as NSString).size(withAttributes: attributes) } ?? .zero
        let spacing: CGFloat = title == nil ? 0 : 4
        let totalWidth = iconSize + spacing + titleSize.width
        var x = rect.midX - totalWidth / 2

        drawTintedSymbol(
            systemSymbol,
            in: NSRect(x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize),
            color: color,
            pointSize: 11,
            weight: .regular
        )
        x += iconSize + spacing
        if let title {
            title.draw(
                at: NSPoint(x: x, y: rect.midY - titleSize.height / 2),
                withAttributes: attributes
            )
        }
    }

    private func drawPill(
        text: String,
        x: CGFloat,
        centerY: CGFloat,
        color: NSColor,
        backgroundAlpha: CGFloat
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: x, y: centerY - 7.5, width: textSize.width + 10, height: 15)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        color.withAlphaComponent(backgroundAlpha).setFill()
        path.fill()
        text.draw(
            at: NSPoint(x: rect.minX + 5, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
        return rect.maxX + 5
    }

    /// Menu-bar rows follow each provider's real windows.
    private func displayWindows(for option: ProviderSettingsOption) -> [QuotaWindow] {
        if let state = statesByProvider[option.id], !state.windows.isEmpty {
            return state.windows
        }

        if option.id == .grok {
            return [.unavailable(id: "weekly", title: L.weeklyTitle)]
        }
        return [
            .unavailable(id: "fiveHour", title: L.fiveHourTitle),
            .unavailable(id: "weekly", title: L.weeklyTitle)
        ]
    }

    private func drawSectionSeparator(y: CGFloat) {
        let rect = NSRect(
            x: Layout.outerPadding,
            y: y - 0.5,
            width: bounds.width - Layout.outerPadding * 2,
            height: 1
        )
        Palette.sectionDivider.setFill()
        rect.fill()
    }

    private func drawTabIcon(option: ProviderSettingsOption?, rect: NSRect, isSelected: Bool) {
        // Filter chrome: monochrome, quieter than product logos in the cards below.
        let color = (isSelected ? Palette.strongText : Palette.secondaryText)
            .withAlphaComponent(isSelected ? 0.90 : 0.48)

        if let option {
            if let mono = monochromeTabIcon(for: option) {
                drawTemplateImage(mono, in: rect, color: color)
                return
            }
            // Fallback glyph circle.
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return
        }

        // “All” — simple 2×2 grid (matches design mock).
        color.setFill()
        let cell: CGFloat = 4.6
        let gap: CGFloat = 2.6
        let gridSize = cell * 2 + gap
        let originX = rect.midX - gridSize / 2
        let originY = rect.midY - gridSize / 2
        for row in 0..<2 {
            for column in 0..<2 {
                let tile = NSRect(
                    x: originX + CGFloat(column) * (cell + gap),
                    y: originY + CGFloat(row) * (cell + gap),
                    width: cell,
                    height: cell
                )
                NSBezierPath(roundedRect: tile, xRadius: 1.1, yRadius: 1.1).fill()
            }
        }
    }

    /// Tab-only monochrome marks (no product tile) so filter icons stay light.
    private func monochromeTabIcon(for option: ProviderSettingsOption) -> NSImage? {
        let resourceName: String?
        switch option.id {
        case .codex:
            resourceName = "TabIconCodex"
        case .grok:
            resourceName = "TabIconGrok"
        default:
            resourceName = nil
        }
        guard let resourceName else { return nil }
        let cacheKey = "tab-\(resourceName)"
        if let cached = iconCache[cacheKey] {
            return cached
        }
        guard let icon = Self.loadProviderIcon(named: resourceName) else {
            return nil
        }
        icon.isTemplate = true
        iconCache[cacheKey] = icon
        return icon
    }

    private func drawTemplateImage(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let appearance = effectiveAppearance
        let size = NSSize(width: max(rect.width, 1), height: max(rect.height, 1))
        let tinted = NSImage(size: size, flipped: false) { bounds in
            appearance.performAsCurrentDrawingAppearance {
                image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
                color.setFill()
                bounds.fill(using: .sourceAtop)
            }
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawWindowIcon(windowID: String, rect: NSRect, muted: Bool = false) {
        let symbolName = windowID.localizedCaseInsensitiveContains("week") ? "calendar" : "clock"
        drawTintedSymbol(
            symbolName,
            in: rect,
            color: muted ? Palette.mutedText : Palette.secondaryText,
            pointSize: 10,
            weight: .medium
        )
    }

    private func drawTintedSymbol(
        _ name: String,
        in rect: NSRect,
        color: NSColor,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let symbol = base.withSymbolConfiguration(config) ?? base
        symbol.isTemplate = true

        let appearance = effectiveAppearance
        let size = NSSize(width: max(rect.width, 1), height: max(rect.height, 1))
        let tinted = NSImage(size: size, flipped: false) { bounds in
            appearance.performAsCurrentDrawingAppearance {
                symbol.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
                color.setFill()
                bounds.fill(using: .sourceAtop)
            }
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func accentColor(for option: ProviderSettingsOption) -> NSColor {
        NSColor(hex: option.accentColorHex) ?? .systemBlue
    }

    private func providerIcon(for option: ProviderSettingsOption) -> NSImage? {
        guard let iconResourceName = option.iconResourceName else {
            return nil
        }
        if let cached = iconCache[iconResourceName] {
            return cached
        }
        guard let icon = Self.loadProviderIcon(named: iconResourceName) else {
            return nil
        }
        iconCache[iconResourceName] = icon
        return icon
    }

    private static func loadProviderIcon(named name: String) -> NSImage? {
        for fileExtension in ["svg", "png"] {
            if let url = ResourceBundle.url(forResource: name, withExtension: fileExtension),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }

        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private enum FooterAction {
    case settings
    case refresh
    case quit
}

private extension NSAppearance {
    var isDarkQuotaAppearance: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
