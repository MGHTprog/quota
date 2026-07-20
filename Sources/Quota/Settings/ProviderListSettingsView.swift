import AppKit

/// Reorderable provider list: enable checkboxes + drag order.
///
/// Plain stack inside a card — no NSTableView / NSScrollView. Provider count is
/// small (max a handful), so rows always fit without a scroll document that can
/// jump out of the viewport or trip Auto Layout inside a clip view.
final class ProviderListSettingsView: NSView {
    private enum Metrics {
        static let rowHeight: CGFloat = 40
        static let iconSize: CGFloat = 26
        static let cornerRadius: CGFloat = 10
        static let cardPadding: CGFloat = 6
        /// Keep empty slots under current rows so the card can grow with more providers later.
        static let minVisibleRows = 3
        static let maxVisibleRows = ProviderDisplayLimits.maxEnabledCount
    }

    private let cardView = NSView()
    private let stack = NSStackView()
    private let pasteboardType = NSPasteboard.PasteboardType("com.quota.provider-row")

    private var optionsByID: [ProviderID: ProviderSettingsOption] = [:]
    private(set) var providerOrder: [ProviderID] = []
    private(set) var enabledIDs: Set<ProviderID> = []

    var onChange: (() -> Void)?

    var selectedCount: Int { enabledIDs.count }
    var maxSelectableCount: Int { ProviderDisplayLimits.maxEnabledCount }

    /// At least `minVisibleRows` tall (breathing room / room for more vendors);
    /// grows with actual rows up to `maxVisibleRows`.
    var preferredHeight: CGFloat {
        let rows = max(providerOrder.count, 1)
        let visible = min(max(rows, Metrics.minVisibleRows), Metrics.maxVisibleRows)
        return CGFloat(visible) * Metrics.rowHeight + Metrics.cardPadding * 2
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        options: [ProviderSettingsOption],
        configuration: ProviderSettingsConfiguration
    ) {
        optionsByID = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        let available = options.map(\.id)
        providerOrder = configuration.resolvedOrder(availableIDs: available)
        if configuration.usesDefaultEnablement {
            enabledIDs = Set(available)
        } else {
            enabledIDs = configuration.enabledProviderIDs.intersection(Set(available))
            if enabledIDs.isEmpty, let first = available.first {
                enabledIDs = [first]
            }
        }
        rebuildRows()
        onChange?()
    }

    func makeConfiguration() -> ProviderSettingsConfiguration {
        ProviderSettingsConfiguration(
            providerOrder: providerOrder,
            enabledProviderIDs: enabledIDs
        )
    }

    private func setup() {
        wantsLayer = true

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = Metrics.cornerRadius
        cardView.layer?.masksToBounds = true
        if #available(macOS 11.0, *) {
            cardView.layer?.cornerCurve = .continuous
        }
        cardView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Pin to top so reserved empty space stays under the last provider (not centered).
        stack.setContentHuggingPriority(.required, for: .vertical)
        cardView.addSubview(stack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.cardPadding),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            // Not tied to card bottom — leftover height is intentional bottom padding.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -Metrics.cardPadding),
        ])

        registerForDraggedTypes([pasteboardType])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cardView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cardView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }

    private func rebuildRows() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, id) in providerOrder.enumerated() {
            let option = optionsByID[id]
            let row = ProviderRowView(
                rowIndex: index,
                providerID: id,
                title: option?.displayName ?? id.rawValue,
                icon: Self.loadIcon(named: option?.iconResourceName, size: Metrics.iconSize),
                isEnabled: enabledIDs.contains(id),
                showsSeparator: index < providerOrder.count - 1,
                pasteboardType: pasteboardType
            )
            row.onToggle = { [weak self] providerID, isOn in
                self?.setEnabled(providerID, isOn: isOn)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true
            stack.addArrangedSubview(row)
        }
    }

    private func setEnabled(_ id: ProviderID, isOn: Bool) {
        if isOn {
            if enabledIDs.count >= ProviderDisplayLimits.maxEnabledCount,
               !enabledIDs.contains(id) {
                NSSound.beep()
                rebuildRows()
                return
            }
            enabledIDs.insert(id)
        } else {
            if enabledIDs.count <= 1, enabledIDs.contains(id) {
                NSSound.beep()
                rebuildRows()
                return
            }
            enabledIDs.remove(id)
        }
        rebuildRows()
        onChange?()
    }

    // MARK: - Drop reorder

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        validateDrop(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        validateDrop(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard
            let sourceString = sender.draggingPasteboard.string(forType: pasteboardType),
            let sourceRow = Int(sourceString),
            providerOrder.indices.contains(sourceRow)
        else {
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)
        let localY = stack.convert(point, from: self).y
        // Default NSView is not flipped: y=0 at bottom. Convert to top-based index.
        let fromTop = stack.bounds.height - localY
        var destination = Int(fromTop / Metrics.rowHeight)
        destination = max(0, min(destination, providerOrder.count))

        var insertAt = destination
        if sourceRow < insertAt {
            insertAt -= 1
        }
        insertAt = max(0, min(insertAt, providerOrder.count - 1))
        guard sourceRow != insertAt else { return false }

        let item = providerOrder.remove(at: sourceRow)
        providerOrder.insert(item, at: insertAt)
        rebuildRows()
        onChange?()
        return true
    }

    private func validateDrop(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: pasteboardType) != nil ? .move : []
    }

    private static func loadIcon(named name: String?, size: CGFloat) -> NSImage? {
        guard let name else { return nil }
        for ext in ["svg", "png"] {
            let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.module.url(forResource: name, withExtension: ext)
            if let image = url.flatMap(NSImage.init(contentsOf:)) {
                image.size = NSSize(width: size, height: size)
                return image
            }
        }
        return nil
    }
}

// MARK: - Row

private final class ProviderRowView: NSView, NSDraggingSource {
    let providerID: ProviderID
    private let rowIndex: Int
    private let pasteboardType: NSPasteboard.PasteboardType
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let handleView = NSImageView()
    private let separator = NSBox()
    private var mouseDownPoint: NSPoint?
    private var isDraggingSession = false

    var onToggle: ((ProviderID, Bool) -> Void)?

    init(
        rowIndex: Int,
        providerID: ProviderID,
        title: String,
        icon: NSImage?,
        isEnabled: Bool,
        showsSeparator: Bool,
        pasteboardType: NSPasteboard.PasteboardType
    ) {
        self.rowIndex = rowIndex
        self.providerID = providerID
        self.pasteboardType = pasteboardType
        super.init(frame: .zero)

        wantsLayer = true

        checkbox.state = isEnabled ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(checkboxToggled)
        checkbox.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        handleView.imageScaling = .scaleProportionallyDown
        handleView.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        if let symbol = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: L.providersDragHint
        ) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            handleView.image = symbol.withSymbolConfiguration(config)
        }
        handleView.toolTip = L.providersDragHint
        handleView.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.isHidden = !showsSeparator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(checkbox)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(handleView)
        addSubview(separator)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: handleView.leadingAnchor, constant: -8),

            handleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            handleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 16),
            handleView.heightAnchor.constraint(equalToConstant: 16),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private enum Metrics {
        static let iconSize: CGFloat = 26
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func checkboxToggled() {
        onToggle?(providerID, checkbox.state == .on)
    }

    private func applyEnabled(_ isOn: Bool) {
        checkbox.state = isOn ? .on : .off
        onToggle?(providerID, isOn)
    }

    /// Checkbox keeps its own hit target; everything else (icon / title / empty) hits the row for toggle + drag.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === checkbox || hit.isDescendant(of: checkbox) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        isDraggingSession = false
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !isDraggingSession else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - start.x, point.y - start.y)
        guard distance > 4 else { return }

        isDraggingSession = true
        let item = NSPasteboardItem()
        item.setString(String(rowIndex), forType: pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            isDraggingSession = false
        }
        // Click (not drag) on the row toggles enable — checkbox still works on its own hit area.
        guard !isDraggingSession, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - start.x, point.y - start.y)
        guard distance <= 4 else { return }

        let handleHit = handleView.frame.insetBy(dx: -8, dy: -8).contains(start)
        if handleHit {
            // Handle is for reorder affordance; a bare click there does not toggle.
            return
        }
        applyEnabled(checkbox.state != .on)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    private func snapshotImage() -> NSImage {
        // Bitmap rep avoids lockFocus issues when the row has no backing store yet.
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
