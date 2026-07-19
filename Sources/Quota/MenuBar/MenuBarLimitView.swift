import AppKit

/// Provider-driven quota panel shown from the menu bar.
final class MenuBarLimitView: NSView {
    private enum Layout {
        static let width: CGFloat = 260
        static let outerPadding: CGFloat = 12
        static let tabHeight: CGFloat = 30
        /// Compact chip width — tabs size to content, not the full panel width.
        static let tabChipWidth: CGFloat = 34
        static let tabGap: CGFloat = 6
        /// Gap between provider cards (includes space for a clearer divider).
        static let cardGap: CGFloat = 14
        /// Small breathing room under the last quota row — not used to match other cards.
        static let cardBottomPadding: CGFloat = 4
        static let footerHeight: CGFloat = 34
        static let iconSize: CGFloat = 28
        static let rowHeight: CGFloat = 44
        static let barHeight: CGFloat = 3.5
        static let lowThreshold: Double = 20
        static let midThreshold: Double = 45

        static func cardHeight(rowCount: Int) -> CGFloat {
            iconSize + 9 + rowHeight * CGFloat(max(1, rowCount)) + cardBottomPadding
        }
    }

    private enum Palette {
        static let panel = NSColor(calibratedWhite: 0.94, alpha: 0.98)
        static let surface = NSColor(calibratedWhite: 0.985, alpha: 0.72)
        static let stroke = NSColor(calibratedWhite: 0.76, alpha: 0.42)
        static let hairline = NSColor(calibratedWhite: 0.70, alpha: 0.20)
        /// Stronger than `hairline` so provider sections separate clearly.
        static let sectionDivider = NSColor(calibratedWhite: 0.52, alpha: 0.38)
        static let text = NSColor.secondaryLabelColor
        static let strongText = NSColor.labelColor
        static let secondaryText = NSColor.secondaryLabelColor
        static let mutedText = NSColor.tertiaryLabelColor
        static let track = NSColor(calibratedWhite: 0.80, alpha: 0.46)
        static let selectedTab = NSColor(calibratedWhite: 1.0, alpha: 0.95)
        static let selectedStroke = NSColor.controlAccentColor.withAlphaComponent(0.45)
        static let unselectedTab = NSColor(calibratedWhite: 0.97, alpha: 0.55)
        static let codexGreen = NSColor(calibratedRed: 0.04, green: 0.62, blue: 0.22, alpha: 1)
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

    override var intrinsicContentSize: NSSize {
        NSSize(width: Layout.width, height: calculatedHeight)
    }

    private var calculatedHeight: CGFloat {
        let visibleOptions = selectedOptions
        let cardHeights = visibleOptions.reduce(CGFloat.zero) { total, option in
            total + Layout.cardHeight(rowCount: max(1, displayWindows(for: option).count))
        }
        let gaps = max(0, visibleOptions.count - 1)
        return Layout.outerPadding
            + Layout.tabHeight
            + 10
            + cardHeights
            + CGFloat(gaps) * Layout.cardGap
            + 5
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
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
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
    /// Prefer hardware key codes — `charactersIgnoringModifiers` is unreliable for "," across layouts/IMEs.
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

        // Allow only Command alone (ignore caps lock via deviceIndependentFlagsMask).
        let commandOnly = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)
        guard commandOnly else { return false }

        switch event.keyCode {
        case PanelKeyCode.comma:
            // macOS Settings convention: ⌘,
            onSettings?()
            return true
        case PanelKeyCode.r:
            onRefresh?()
            return true
        case PanelKeyCode.q:
            onQuit?()
            return true
        default:
            // Fallback for unusual keyboard layouts that remapped letter keys only.
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
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        Palette.panel.setFill()
        path.fill()
        Palette.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawTabs() {
        let top = bounds.height - Layout.outerPadding
        let y = top - Layout.tabHeight
        // Fixed-size chips, left-aligned — do not stretch across the panel.
        // Scales to more providers without each tab becoming a wide empty block.
        let chipWidth = tabChipWidth()
        var x = Layout.outerPadding

        let allRect = NSRect(x: x, y: y, width: chipWidth, height: Layout.tabHeight)
        drawTab(rect: allRect, isSelected: selectedProviderID == nil, option: nil)
        tabRects.append((nil, allRect))
        x += chipWidth + Layout.tabGap

        for option in providerOptions {
            let rect = NSRect(x: x, y: y, width: chipWidth, height: Layout.tabHeight)
            drawTab(rect: rect, isSelected: selectedProviderID == option.id, option: option)
            tabRects.append((option.id, rect))
            x += chipWidth + Layout.tabGap
        }
    }

    /// Prefer a comfortable chip size; shrink only when many providers would overflow.
    private func tabChipWidth() -> CGFloat {
        let count = CGFloat(providerOptions.count + 1)
        let available = bounds.width - Layout.outerPadding * 2
        let natural = count * Layout.tabChipWidth + max(0, count - 1) * Layout.tabGap
        guard natural > available, count > 0 else {
            return Layout.tabChipWidth
        }
        let gapTotal = max(0, count - 1) * Layout.tabGap
        return max(28, floor((available - gapTotal) / count))
    }

    private func drawCards() {
        var y = bounds.height - Layout.outerPadding - Layout.tabHeight - 10
        for (index, option) in selectedOptions.enumerated() {
            let height = Layout.cardHeight(rowCount: max(1, displayWindows(for: option).count))
            y -= height
            let rect = NSRect(
                x: Layout.outerPadding,
                y: y,
                width: bounds.width - Layout.outerPadding * 2,
                height: height
            )
            drawProviderCard(option: option, rect: rect)
            if index < selectedOptions.count - 1 {
                drawSectionSeparator(y: y - Layout.cardGap / 2)
            }
            y -= Layout.cardGap
        }
    }

    private func drawFooter() {
        let lineY = Layout.footerHeight + 3
        Palette.hairline.setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: Layout.outerPadding, y: lineY),
            to: NSPoint(x: bounds.width - Layout.outerPadding, y: lineY)
        )

        let availableWidth = bounds.width - Layout.outerPadding * 2
        let buttonWidth = availableWidth / 3
        let actions: [(FooterAction, String, String)] = [
            (.settings, "gearshape", L.settings),
            (.refresh, "arrow.clockwise", L.refresh),
            (.quit, "power", L.quit)
        ]

        for (index, item) in actions.enumerated() {
            let rect = NSRect(
                x: Layout.outerPadding + CGFloat(index) * buttonWidth,
                y: 3,
                width: buttonWidth,
                height: 26
            )
            drawFooterButton(systemSymbol: item.1, title: item.2, rect: rect)
            footerRects.append((item.0, rect))

            if index > 0 {
                Palette.hairline.setStroke()
                NSBezierPath.strokeLine(
                    from: NSPoint(x: rect.minX, y: rect.minY + 7),
                    to: NSPoint(x: rect.minX, y: rect.maxY - 7)
                )
            }
        }
    }

    private func drawTab(rect: NSRect, isSelected: Bool, option: ProviderSettingsOption?) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if isSelected {
            Palette.selectedTab.setFill()
            path.fill()
            Palette.selectedStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            Palette.unselectedTab.setFill()
            path.fill()
            Palette.stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let iconSize: CGFloat = 15
        let iconRect = NSRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        drawTabIcon(option: option, rect: iconRect, isSelected: isSelected)
    }

    private func drawProviderCard(option: ProviderSettingsOption, rect: NSRect) {
        let state = statesByProvider[option.id]
        let identity = state?.identity ?? ProviderIdentity(displayName: option.displayName, plan: nil)
        // Only real product windows (Grok = weekly only; Codex = 5h + weekly).
        // Do not invent empty quota rows for windows the provider does not have.
        let windows = displayWindows(for: option)

        let headerY = rect.maxY - Layout.iconSize
        drawProviderIcon(option: option, rect: NSRect(
            x: rect.minX,
            y: headerY,
            width: Layout.iconSize,
            height: Layout.iconSize
        ))

        drawHeader(identity: identity, badges: state?.badges ?? [], rect: NSRect(
            x: rect.minX + Layout.iconSize + 9,
            y: headerY,
            width: rect.width - Layout.iconSize - 9,
            height: Layout.iconSize
        ))

        var y = headerY - 9
        for window in windows {
            y -= Layout.rowHeight
            drawWindow(window, rect: NSRect(x: rect.minX, y: y, width: rect.width, height: Layout.rowHeight))
        }
    }

    private func drawHeader(identity: ProviderIdentity, badges: [ProviderBadge], rect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: Palette.strongText
        ]
        let title = identity.displayName
        title.draw(at: NSPoint(x: rect.minX, y: rect.midY - 9), withAttributes: titleAttributes)

        var x = rect.minX + (title as NSString).size(withAttributes: titleAttributes).width + 8
        if let plan = identity.plan, !plan.isEmpty {
            x = drawPill(text: plan, x: x, centerY: rect.midY, color: Palette.codexGreen, backgroundAlpha: 0.075)
        }
        for badge in badges.prefix(2) {
            x = drawPill(text: badge.text, x: x, centerY: rect.midY, color: Palette.secondaryText, backgroundAlpha: 0.055)
        }
    }

    private func drawWindow(_ window: QuotaWindow, rect: NSRect) {
        let clamped = min(max(window.remainingPercent, 0), 100)
        let percentText = window.isAvailable ? "\(Int(clamped.rounded()))%" : "--%"
        let percent = window.isAvailable ? clamped : nil

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: Palette.strongText
        ]
        let percentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: percent.map(barColor) ?? Palette.secondaryText
        ]
        let remainingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: Palette.secondaryText
        ]
        let resetAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: Palette.mutedText
        ]

        let titleX = rect.minX + 18
        let titleY = rect.maxY - 18
        let rightY = titleY - 1
        let resetY = rect.minY + 4

        let iconRect = NSRect(x: rect.minX, y: titleY + 1, width: 12, height: 12)
        drawWindowIcon(windowID: window.id, rect: iconRect)

        window.title.draw(at: NSPoint(x: titleX, y: titleY), withAttributes: titleAttributes)

        let remainingSize = (L.remaining as NSString).size(withAttributes: remainingAttributes)
        let percentSize = (percentText as NSString).size(withAttributes: percentAttributes)
        let percentColumnWidth = ("100%" as NSString).size(withAttributes: percentAttributes).width
        let percentColumnX = rect.maxX - percentColumnWidth
        let remainingX = percentColumnX - 5 - remainingSize.width

        L.remaining.draw(
            at: NSPoint(x: remainingX, y: rightY),
            withAttributes: remainingAttributes
        )
        percentText.draw(
            at: NSPoint(x: percentColumnX + percentColumnWidth - percentSize.width, y: rightY),
            withAttributes: percentAttributes
        )

        let barRect = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: Layout.barHeight)
        drawProgressBar(in: barRect, percent: percent, color: percent.map(barColor) ?? .tertiaryLabelColor)

        let resetText = window.isAvailable ? window.resetText : "\(L.reset) --"
        resetText.draw(at: NSPoint(x: titleX, y: resetY), withAttributes: resetAttributes)
    }

    private func drawProgressBar(in rect: NSRect, percent: Double?, color: NSColor) {
        let background = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        Palette.track.setFill()
        background.fill()

        guard let percent else { return }
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
            icon.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        accentColor(for: option).setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: option.fallbackGlyph.count > 1 ? 9 : 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (option.fallbackGlyph as NSString).size(withAttributes: attributes)
        option.fallbackGlyph.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawFooterButton(systemSymbol: String, title: String, rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: Palette.secondaryText
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let iconSize: CGFloat = 13
        let totalWidth = iconSize + 5 + titleSize.width
        var x = rect.midX - totalWidth / 2

        if let image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: title) {
            image.draw(
                in: NSRect(x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 0.56
            )
        }
        x += iconSize + 5
        title.draw(at: NSPoint(x: x, y: rect.midY - titleSize.height / 2), withAttributes: attributes)
    }

    private func drawPill(text: String, x: CGFloat, centerY: CGFloat, color: NSColor, backgroundAlpha: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: color
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: x, y: centerY - 8, width: textSize.width + 11, height: 16)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        color.withAlphaComponent(backgroundAlpha).setFill()
        path.fill()
        text.draw(at: NSPoint(x: rect.minX + 5.5, y: rect.midY - textSize.height / 2), withAttributes: attributes)
        return rect.maxX + 5
    }

    /// Menu-bar rows follow each provider's real windows.
    /// Offline placeholders still match product shape (not a fake second Grok row).
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

    private func barColor(for percent: Double) -> NSColor {
        switch percent {
        case ..<Layout.lowThreshold:
            return NSColor(calibratedRed: 0.86, green: 0.20, blue: 0.16, alpha: 0.92)
        case ..<Layout.midThreshold:
            return NSColor(calibratedRed: 0.92, green: 0.46, blue: 0.12, alpha: 0.92)
        default:
            return NSColor(calibratedRed: 0.15, green: 0.58, blue: 0.28, alpha: 0.92)
        }
    }

    private func drawSectionSeparator(y: CGFloat) {
        // Slightly inset, thicker fill — more visible than a 1px hairline stroke.
        let inset: CGFloat = 4
        let rect = NSRect(
            x: Layout.outerPadding + inset,
            y: y - 0.5,
            width: bounds.width - Layout.outerPadding * 2 - inset * 2,
            height: 1
        )
        Palette.sectionDivider.setFill()
        rect.fill()
    }

    private func drawTabIcon(option: ProviderSettingsOption?, rect: NSRect, isSelected: Bool) {
        if let option {
            if let icon = providerIcon(for: option) {
                icon.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                return
            }

            accentColor(for: option).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return
        }

        let color = isSelected ? NSColor.systemBlue : Palette.secondaryText
        color.setStroke()
        let cell: CGFloat = 4.4
        for row in 0..<2 {
            for column in 0..<2 {
                let tile = NSRect(
                    x: rect.minX + CGFloat(column) * (cell + 3.5),
                    y: rect.minY + CGFloat(row) * (cell + 3.5),
                    width: cell,
                    height: cell
                )
                let path = NSBezierPath(roundedRect: tile, xRadius: 1.5, yRadius: 1.5)
                path.lineWidth = 1.35
                path.stroke()
            }
        }
    }

    private func drawWindowIcon(windowID: String, rect: NSRect) {
        let symbolName = windowID.localizedCaseInsensitiveContains("week") ? "calendar" : "clock"
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 0.62
        )
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
            let url = Bundle.main.url(forResource: name, withExtension: fileExtension)
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
            if let image = url.flatMap(NSImage.init(contentsOf:)) {
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
