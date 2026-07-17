import AppKit

/// Provider-driven quota panel shown from the menu bar.
final class MenuBarLimitView: NSView {
    private enum Layout {
        static let width: CGFloat = 260
        static let outerPadding: CGFloat = 12
        static let tabHeight: CGFloat = 32
        static let tabGap: CGFloat = 6
        static let cardGap: CGFloat = 10
        static let footerHeight: CGFloat = 34
        static let iconSize: CGFloat = 28
        static let rowHeight: CGFloat = 44
        static let barHeight: CGFloat = 3.5
        static let lowThreshold: Double = 20
        static let midThreshold: Double = 45
    }

    private enum Palette {
        static let panel = NSColor(calibratedWhite: 0.94, alpha: 0.98)
        static let surface = NSColor(calibratedWhite: 0.985, alpha: 0.72)
        static let stroke = NSColor(calibratedWhite: 0.76, alpha: 0.42)
        static let hairline = NSColor(calibratedWhite: 0.70, alpha: 0.20)
        static let text = NSColor.secondaryLabelColor
        static let strongText = NSColor.labelColor
        static let secondaryText = NSColor.secondaryLabelColor
        static let mutedText = NSColor.tertiaryLabelColor
        static let track = NSColor(calibratedWhite: 0.80, alpha: 0.46)
        static let selectedTab = NSColor(calibratedWhite: 0.99, alpha: 0.86)
        static let selectedStroke = NSColor.controlAccentColor.withAlphaComponent(0.24)
        static let codexGreen = NSColor(calibratedRed: 0.04, green: 0.62, blue: 0.22, alpha: 1)
    }

    static var preferredSize: NSSize {
        NSSize(width: Layout.width, height: 250)
    }

    var onSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    private let codexIcon = MenuBarLimitView.loadProviderIcon(named: "ProviderIconCodex")
    private var providerOptions: [ProviderSettingsOption] = []
    private var statesByProvider: [ProviderID: ProviderQuotaState] = [:]
    private var errorsByProvider: [ProviderID: Error] = [:]
    private var selectedProviderID: ProviderID?
    private var tabRects: [(id: ProviderID?, rect: NSRect)] = []
    private var footerRects: [(action: FooterAction, rect: NSRect)] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: Layout.width, height: calculatedHeight)
    }

    private var calculatedHeight: CGFloat {
        let visibleOptions = selectedOptions
        let cardHeights = visibleOptions.reduce(CGFloat.zero) { total, option in
            total + cardHeight(for: option.id)
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
        let providerIDs = Set(providerOptions.map(\.id))
        errorsByProvider = errorsByProvider.filter { providerIDs.contains($0.key) }
        for state in states {
            errorsByProvider[state.providerID] = nil
        }

        if let selectedProviderID,
           !providers.contains(where: { $0.id == selectedProviderID }) {
            self.selectedProviderID = nil
        }

        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func updateFailure(_ error: Error, providerID: ProviderID) {
        errorsByProvider[providerID] = error
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
            selectedProviderID = tab.id
            invalidateIntrinsicContentSize()
            setFrameSize(intrinsicContentSize)
            needsDisplay = true
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
        var x = Layout.outerPadding
        let allWidth: CGFloat = 36
        let allRect = NSRect(x: x, y: top - Layout.tabHeight, width: allWidth, height: Layout.tabHeight)
        drawTab(rect: allRect, isSelected: selectedProviderID == nil, providerID: nil)
        tabRects.append((nil, allRect))
        x += allWidth + Layout.tabGap

        let widths = providerTabWidths(availableX: bounds.width - Layout.outerPadding - x)
        for (option, tabWidth) in zip(providerOptions, widths) {
            let rect = NSRect(x: x, y: top - Layout.tabHeight, width: tabWidth, height: Layout.tabHeight)
            drawTab(rect: rect, isSelected: selectedProviderID == option.id, providerID: option.id)
            tabRects.append((option.id, rect))
            x += tabWidth + Layout.tabGap
        }
    }

    private func drawCards() {
        var y = bounds.height - Layout.outerPadding - Layout.tabHeight - 10
        for (index, option) in selectedOptions.enumerated() {
            let height = cardHeight(for: option.id)
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

    private func drawTab(rect: NSRect, isSelected: Bool, providerID: ProviderID?) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (isSelected ? Palette.selectedTab : Palette.surface).setFill()
        path.fill()
        (isSelected ? Palette.selectedStroke : Palette.stroke).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconSize: CGFloat = 15
        let iconRect = NSRect(
            x: rect.midX - iconSize / 2,
            y: rect.midY - iconSize / 2 + 1.2,
            width: iconSize,
            height: iconSize
        )
        drawTabIcon(providerID: providerID, rect: iconRect, isSelected: isSelected)

        if let providerID {
            let progress = statesByProvider[providerID].flatMap(firstAvailablePercent)
            let barRect = NSRect(x: rect.minX + 8, y: rect.minY + 5, width: rect.width - 16, height: 2.5)
            drawProgressBar(in: barRect, percent: progress, color: progress.map(barColor) ?? .tertiaryLabelColor)
        }
    }

    private func drawProviderCard(option: ProviderSettingsOption, rect: NSRect) {
        let state = statesByProvider[option.id]
        let identity = state?.identity ?? ProviderIdentity(displayName: option.displayName, plan: nil)
        let windows = state?.windowsForCompactDisplay() ?? [.empty, .empty]

        let headerY = rect.maxY - Layout.iconSize
        drawProviderIcon(title: identity.displayName, providerID: option.id, rect: NSRect(
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
        if let error = errorsByProvider[option.id], state == nil {
            drawError(error, at: NSPoint(x: rect.minX, y: y + 4), width: rect.width)
            return
        }

        for window in windows {
            y -= Layout.rowHeight
            drawWindow(window, rect: NSRect(x: rect.minX, y: y, width: rect.width, height: Layout.rowHeight))
        }

        if let error = errorsByProvider[option.id] {
            drawError(error, at: NSPoint(x: rect.minX, y: rect.minY + 2), width: rect.width)
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

    private func drawProviderIcon(title: String, providerID: ProviderID, rect: NSRect) {
        if providerID == .codex, let codexIcon {
            codexIcon.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        providerID == .codex ? Palette.codexGreen.setFill() : accentColor(for: providerID).setFill()
        path.fill()

        if providerID == .codex {
            drawCodexMark(in: rect.insetBy(dx: 5, dy: 5), color: .white, lineWidth: 1.8)
            return
        }

        let symbol = String(title.prefix(1)).uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (symbol as NSString).size(withAttributes: attributes)
        symbol.draw(
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

    private func drawError(_ error: Error, at point: NSPoint, width: CGFloat) {
        let text = "\(L.refreshFailedPrefix): \(error.localizedDescription)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.systemRed
        ]
        let rect = NSRect(x: point.x, y: point.y, width: width, height: 28)
        (text as NSString).draw(in: rect, withAttributes: attributes)
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

    private func cardHeight(for providerID: ProviderID) -> CGFloat {
        if statesByProvider[providerID] == nil, errorsByProvider[providerID] != nil {
            return 108
        }
        return Layout.iconSize + 9 + Layout.rowHeight * 2
    }

    private func firstAvailablePercent(_ state: ProviderQuotaState) -> Double? {
        state.windows.first(where: \.isAvailable)?.remainingPercent
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
        Palette.hairline.setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: Layout.outerPadding, y: y),
            to: NSPoint(x: bounds.width - Layout.outerPadding, y: y)
        )
    }

    private func drawTabIcon(providerID: ProviderID?, rect: NSRect, isSelected: Bool) {
        if let providerID {
            if providerID == .codex {
                if let codexIcon {
                    codexIcon.draw(
                        in: rect,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1
                    )
                    return
                }
                let iconRect = rect.insetBy(dx: 1.5, dy: 1.5)
                let background = NSBezierPath(roundedRect: iconRect, xRadius: 4, yRadius: 4)
                Palette.codexGreen.setFill()
                background.fill()
                drawCodexMark(in: iconRect.insetBy(dx: 2.8, dy: 2.8), color: .white, lineWidth: 1.0)
            } else {
                accentColor(for: providerID).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            }
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

    private func drawCodexMark(in rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.28
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3
            let cx = center.x + cos(angle) * radius * 0.72
            let cy = center.y + sin(angle) * radius * 0.72
            let oval = NSRect(
                x: cx - radius,
                y: cy - radius * 0.62,
                width: radius * 2,
                height: radius * 1.24
            )
            var transform = AffineTransform(translationByX: cx, byY: cy)
            transform.rotate(byRadians: angle)
            transform.translate(x: -cx, y: -cy)
            let path = NSBezierPath(ovalIn: oval)
            path.transform(using: transform)
            path.lineWidth = lineWidth
            path.stroke()
        }
    }

    private func accentColor(for providerID: ProviderID) -> NSColor {
        let colors: [NSColor] = [.systemGreen, .systemBlue, .systemPurple, .systemOrange, .systemTeal]
        let value = providerID.rawValue.unicodeScalars.reduce(0) { partial, scalar in
            partial &+ Int(scalar.value)
        }
        let index = value % colors.count
        return colors[index]
    }

    private func providerTabWidths(availableX: CGFloat) -> [CGFloat] {
        guard !providerOptions.isEmpty else { return [] }

        let naturalWidths = providerOptions.map { _ -> CGFloat in
            return 36
        }
        let totalGap = CGFloat(max(0, providerOptions.count - 1)) * Layout.tabGap
        let naturalTotal = naturalWidths.reduce(0, +) + totalGap
        guard naturalTotal > availableX else { return naturalWidths }

        let scale = max(0.72, (availableX - totalGap) / naturalWidths.reduce(0, +))
        return naturalWidths.map { max(36, floor($0 * scale)) }
    }

    private static func loadProviderIcon(named name: String) -> NSImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }
}

private enum FooterAction {
    case settings
    case refresh
    case quit
}
