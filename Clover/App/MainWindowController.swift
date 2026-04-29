import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let rootViewController: RootSplitViewController
    private weak var layoutToolbarItem: NSToolbarItem?
    private weak var layoutToolbarControl: ToolbarPickerControl?
    private weak var viewModeToolbarItem: NSToolbarItem?
    private weak var viewModeToolbarControl: ToolbarPickerControl?
    private var layoutPopover: NSPopover?

    init(environment: AppEnvironment) {
        rootViewController = RootSplitViewController(environment: environment)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clover"
        window.center()
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentViewController = rootViewController
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "CloverToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func refreshActivePane(_ sender: Any?) {
        rootViewController.refreshActivePane()
    }

    @objc func focusActivePathInput(_ sender: Any?) {
        rootViewController.focusActivePathInput()
    }

    @objc func createFolderInActivePane(_ sender: Any?) {
        rootViewController.createFolderInActivePane()
    }

    @objc func renameSelectedItemInActivePane(_ sender: Any?) {
        rootViewController.renameSelectedItemInActivePane()
    }

    @objc func copySelectedItemsInActivePane(_ sender: Any?) {
        rootViewController.copySelectedItemsInActivePane()
    }

    @objc func moveSelectedItemsInActivePane(_ sender: Any?) {
        rootViewController.moveSelectedItemsInActivePane()
    }

    @objc func trashSelectedItemsInActivePane(_ sender: Any?) {
        rootViewController.trashSelectedItemsInActivePane()
    }

    func setPaneLayout(_ layout: PaneLayout) {
        rootViewController.setPaneLayout(layout)
        updateLayoutButton()
    }

    func setFileViewMode(_ mode: FileViewMode) {
        rootViewController.setFileViewModeInActivePane(mode)
        updateViewModeButton()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .viewMode, .paneLayout, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .viewMode, .paneLayout, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .paneLayout {
            return makeLayoutToolbarItem(identifier: itemIdentifier)
        }
        if itemIdentifier == .viewMode {
            return makeViewModeToolbarItem(identifier: itemIdentifier)
        }
        guard itemIdentifier == .refresh else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = L10n.refresh
        item.paletteLabel = L10n.refresh
        item.image = AppIconProvider.image(.refresh, accessibilityDescription: L10n.refresh)
        item.target = self
        item.action = #selector(refreshActivePane(_:))
        return item
    }

    private func makeLayoutToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L10n.layout
        item.paletteLabel = L10n.layout
        let control = ToolbarPickerControl()
        control.target = self
        control.action = #selector(showLayoutPicker(_:))
        control.translatesAutoresizingMaskIntoConstraints = false
        item.view = control
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: 46),
            control.heightAnchor.constraint(equalToConstant: 28)
        ])
        layoutToolbarItem = item
        layoutToolbarControl = control
        updateLayoutButton()
        return item
    }

    private func makeViewModeToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L10n.viewModeList
        item.paletteLabel = L10n.viewModeList
        let control = ToolbarPickerControl()
        control.target = self
        control.action = #selector(toggleViewMode(_:))
        control.translatesAutoresizingMaskIntoConstraints = false
        item.view = control
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            control.widthAnchor.constraint(lessThanOrEqualToConstant: 92),
            control.heightAnchor.constraint(equalToConstant: 28)
        ])
        viewModeToolbarItem = item
        viewModeToolbarControl = control
        updateViewModeButton()
        return item
    }

    private func updateLayoutButton() {
        let layout = rootViewController.currentPaneLayout
        layoutToolbarItem?.image = layout.toolbarImage
        layoutToolbarItem?.label = L10n.layout
        layoutToolbarItem?.paletteLabel = L10n.layout
        layoutToolbarItem?.toolTip = layout.displayName
        layoutToolbarControl?.configure(title: nil, image: layout.toolbarImage, toolTip: layout.displayName)
    }

    private func updateViewModeButton() {
        let mode = rootViewController.currentFileViewMode
        let title = mode == .list ? L10n.viewModeList : L10n.viewModeGrid
        viewModeToolbarItem?.image = viewModeImage
        viewModeToolbarItem?.label = title
        viewModeToolbarItem?.paletteLabel = title
        viewModeToolbarItem?.toolTip = title
        viewModeToolbarControl?.configure(title: title, image: viewModeImage, toolTip: title)
    }

    private var viewModeImage: NSImage? {
        let symbol: AppSymbol = rootViewController.currentFileViewMode == .list ? .list : .grid
        return AppIconProvider.image(symbol, accessibilityDescription: nil)
    }

    @objc private func toggleViewMode(_ sender: Any?) {
        let nextMode: FileViewMode = rootViewController.currentFileViewMode == .list ? .grid : .list
        setFileViewMode(nextMode)
    }

    @objc private func showLayoutPicker(_ sender: Any?) {
        let controller = LayoutPickerViewController(selectedLayout: rootViewController.currentPaneLayout)
        controller.selectionHandler = { [weak self] layout in
            self?.layoutPopover?.close()
            self?.setPaneLayout(layout)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 174, height: 126)
        popover.contentViewController = controller
        layoutPopover = popover
        if let itemView = layoutToolbarControl ?? layoutToolbarItem?.view {
            popover.show(relativeTo: itemView.bounds, of: itemView, preferredEdge: .maxY)
        } else if let contentView = window?.contentView {
            let anchor = NSRect(x: contentView.bounds.midX - 87, y: contentView.bounds.maxY - 1, width: 174, height: 1)
            popover.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        }
    }
}

private final class ToolbarPickerControl: NSControl {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage())
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        stackView.fittingSize
    }

    func configure(title: String?, image: NSImage?, toolTip: String) {
        titleField.stringValue = title ?? ""
        titleField.isHidden = title?.isEmpty ?? true
        iconView.image = image
        self.toolTip = toolTip
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        highlight(true)
        sendAction(action, to: target)
        highlight(false)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = .secondaryLabelColor
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 5
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleField)
        stackView.addArrangedSubview(chevronView)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            chevronView.widthAnchor.constraint(equalToConstant: 10),
            chevronView.heightAnchor.constraint(equalToConstant: 10)
        ])
    }

    private func highlight(_ isHighlighted: Bool) {
        layer?.backgroundColor = isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
    }
}

private extension NSToolbarItem.Identifier {
    static let refresh = NSToolbarItem.Identifier("CloverToolbar.Refresh")
    static let viewMode = NSToolbarItem.Identifier("CloverToolbar.ViewMode")
    static let paneLayout = NSToolbarItem.Identifier("CloverToolbar.PaneLayout")
}

private extension PaneLayout {
    var displayName: String {
        switch self {
        case .single:
            return "Single Pane"
        case .twoVertical:
            return "Two Panes Vertical"
        case .twoHorizontal:
            return "Two Panes Horizontal"
        case .fourGrid:
            return "Four Panes"
        }
    }

    var toolbarImage: NSImage {
        LayoutIconFactory.image(for: self, highlighted: false)
    }

    var menuTag: Int {
        switch self {
        case .single:
            return 1
        case .twoVertical:
            return 2
        case .twoHorizontal:
            return 3
        case .fourGrid:
            return 4
        }
    }

    init?(menuTag: Int) {
        switch menuTag {
        case 1:
            self = .single
        case 2:
            self = .twoVertical
        case 3:
            self = .twoHorizontal
        case 4:
            self = .fourGrid
        default:
            return nil
        }
    }
}

private final class LayoutPickerViewController: NSViewController {
    var selectionHandler: ((PaneLayout) -> Void)?

    private let selectedLayout: PaneLayout

    init(selectedLayout: PaneLayout) {
        self.selectedLayout = selectedLayout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 12

        let grid = NSGridView(views: [
            [makeButton(.single), makeButton(.twoVertical), makeButton(.twoHorizontal), makeButton(.fourGrid)]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        rootView.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -14)
        ])

        view = rootView
    }

    private func makeButton(_ layout: PaneLayout) -> NSButton {
        let button = NSButton(image: LayoutIconFactory.image(for: layout, highlighted: layout == selectedLayout), target: self, action: #selector(selectLayout(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = NSButton.BezelStyle.regularSquare
        button.isBordered = false
        button.imagePosition = NSControl.ImagePosition.imageOnly
        button.tag = layout.menuTag
        button.toolTip = layout.displayName
        button.setAccessibilityLabel(layout.displayName)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    @objc private func selectLayout(_ sender: NSButton) {
        guard let layout = PaneLayout(menuTag: sender.tag) else { return }
        selectionHandler?(layout)
    }
}

private enum LayoutIconFactory {
    static func image(for layout: PaneLayout, highlighted: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let strokeColor = highlighted ? NSColor.systemGreen : NSColor.secondaryLabelColor
        strokeColor.setStroke()

        let lineWidth: CGFloat = highlighted ? 2 : 1.6
        let outer = NSRect(x: 3, y: 3, width: 16, height: 16)
        let path = NSBezierPath(rect: outer)
        path.lineWidth = lineWidth
        path.stroke()

        let dividers = dividers(for: layout, in: outer)
        for divider in dividers {
            let dividerPath = NSBezierPath()
            dividerPath.lineWidth = lineWidth
            dividerPath.move(to: divider.start)
            dividerPath.line(to: divider.end)
            dividerPath.stroke()
        }

        return image
    }

    private static func dividers(for layout: PaneLayout, in rect: NSRect) -> [(start: NSPoint, end: NSPoint)] {
        let midX = rect.midX
        let midY = rect.midY
        switch layout {
        case .single:
            return []
        case .twoVertical:
            return [(NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: rect.maxY))]
        case .twoHorizontal:
            return [(NSPoint(x: rect.minX, y: midY), NSPoint(x: rect.maxX, y: midY))]
        case .fourGrid:
            return [
                (NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: rect.maxY)),
                (NSPoint(x: rect.minX, y: midY), NSPoint(x: rect.maxX, y: midY))
            ]
        }
    }
}
