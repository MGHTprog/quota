import AppKit

/// Reorderable provider list: enable checkboxes + drag order.
/// First enabled row is primary (leftmost tab; Touch Bar when available).
final class ProviderListSettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private enum Column {
        static let enable = NSUserInterfaceItemIdentifier("enable")
        static let provider = NSUserInterfaceItemIdentifier("provider")
        static let primary = NSUserInterfaceItemIdentifier("primary")
    }

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let pasteboardType = NSPasteboard.PasteboardType("com.quota.provider-row")

    private var optionsByID: [ProviderID: ProviderSettingsOption] = [:]
    private(set) var providerOrder: [ProviderID] = []
    private(set) var enabledIDs: Set<ProviderID> = []

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
        tableView.reloadData()
    }

    func makeConfiguration() -> ProviderSettingsConfiguration {
        ProviderSettingsConfiguration(
            providerOrder: providerOrder,
            enabledProviderIDs: enabledIDs
        )
    }

    private func setup() {
        wantsLayer = true

        let enableColumn = NSTableColumn(identifier: Column.enable)
        enableColumn.title = ""
        enableColumn.width = 28
        enableColumn.minWidth = 28
        enableColumn.maxWidth = 28

        let providerColumn = NSTableColumn(identifier: Column.provider)
        providerColumn.title = ""
        providerColumn.width = 220
        providerColumn.minWidth = 120

        let primaryColumn = NSTableColumn(identifier: Column.primary)
        primaryColumn.title = ""
        primaryColumn.width = 100
        primaryColumn.minWidth = 80

        tableView.addTableColumn(enableColumn)
        tableView.addTableColumn(providerColumn)
        tableView.addTableColumn(primaryColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 30
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.style = .plain
        tableView.registerForDraggedTypes([pasteboardType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        providerOrder.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, providerOrder.indices.contains(row) else { return nil }
        let id = providerOrder[row]
        let option = optionsByID[id]

        switch tableColumn.identifier {
        case Column.enable:
            let cellID = NSUserInterfaceItemIdentifier("EnableCell")
            let button: NSButton
            if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? NSButton {
                button = existing
            } else {
                button = NSButton(checkboxWithTitle: "", target: self, action: #selector(enableToggled(_:)))
                button.identifier = cellID
            }
            button.tag = row
            button.state = enabledIDs.contains(id) ? .on : .off
            return button

        case Column.provider:
            let cellID = NSUserInterfaceItemIdentifier("ProviderCell")
            let stack: NSStackView
            if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? NSStackView {
                stack = existing
            } else {
                stack = NSStackView()
                stack.identifier = cellID
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 8
                let icon = NSImageView()
                icon.imageScaling = .scaleProportionallyUpOrDown
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
                icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
                let label = NSTextField(labelWithString: "")
                label.font = .systemFont(ofSize: 13)
                label.lineBreakMode = .byTruncatingTail
                stack.addArrangedSubview(icon)
                stack.addArrangedSubview(label)
            }
            let iconView = stack.arrangedSubviews[0] as? NSImageView
            let label = stack.arrangedSubviews[1] as? NSTextField
            label?.stringValue = option?.displayName ?? id.rawValue
            iconView?.image = Self.loadIcon(named: option?.iconResourceName)
            iconView?.toolTip = option?.displayName
            stack.toolTip = option?.displayName
            return stack

        case Column.primary:
            let cellID = NSUserInterfaceItemIdentifier("PrimaryCell")
            let label: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                label = existing
            } else {
                label = NSTextField(labelWithString: "")
                label.identifier = cellID
                label.font = .systemFont(ofSize: 11, weight: .medium)
                label.textColor = .secondaryLabelColor
            }
            let isPrimary = enabledIDs.contains(id)
                && providerOrder.first(where: { enabledIDs.contains($0) }) == id
            label.stringValue = isPrimary ? L.providerPrimaryBadge : ""
            return label

        default:
            return nil
        }
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: pasteboardType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard dropOperation == .above else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let items = info.draggingPasteboard.pasteboardItems,
            let sourceString = items.first?.string(forType: pasteboardType),
            let sourceRow = Int(sourceString),
            providerOrder.indices.contains(sourceRow)
        else {
            return false
        }

        var destination = row
        if sourceRow < destination {
            destination -= 1
        }
        destination = max(0, min(destination, providerOrder.count - 1))
        guard sourceRow != destination else { return false }

        let item = providerOrder.remove(at: sourceRow)
        providerOrder.insert(item, at: destination)
        tableView.reloadData()
        return true
    }

    @objc private func enableToggled(_ sender: NSButton) {
        let row = sender.tag
        guard providerOrder.indices.contains(row) else { return }
        let id = providerOrder[row]

        if sender.state == .on {
            if enabledIDs.count >= ProviderDisplayLimits.maxEnabledCount,
               !enabledIDs.contains(id) {
                sender.state = .off
                NSSound.beep()
                return
            }
            enabledIDs.insert(id)
        } else {
            // Keep at least one enabled provider.
            if enabledIDs.count <= 1, enabledIDs.contains(id) {
                sender.state = .on
                NSSound.beep()
                return
            }
            enabledIDs.remove(id)
        }
        tableView.reloadData()
    }

    private static func loadIcon(named name: String?) -> NSImage? {
        guard let name else { return nil }
        for ext in ["svg", "png"] {
            let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.module.url(forResource: name, withExtension: ext)
            if let image = url.flatMap(NSImage.init(contentsOf:)) {
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }
        return nil
    }
}
