import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSUserInterfaceValidations {
    private let rootViewController: RootSplitViewController
    private weak var layoutToolbarItem: NSToolbarItem?
    private weak var layoutToolbarButton: NSButton?
    private weak var viewModeToolbarItem: NSToolbarItem?
    private weak var viewModeToolbarButton: NSButton?
    private var layoutPopover: NSPopover?
    private let environment: AppEnvironment

    init(environment: AppEnvironment, restoredWorkspace: Workspace? = nil) {
        self.environment = environment
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
        rootViewController.activePaneChangeHandler = { [weak self] in
            self?.updateViewModeButton()
            self?.updateWindowTitle()
        }
        rootViewController.activePanePathChangeHandler = { [weak self] _ in
            self?.updateWindowTitle()
        }

        let toolbar = NSToolbar(identifier: "CloverToolbar")
        toolbar.delegate = self
        window.toolbar = toolbar

        if let restoredWorkspace {
            rootViewController.loadViewIfNeeded()
            rootViewController.restore(from: restoredWorkspace)
            let restoredFrame = NSRectFromString(restoredWorkspace.windowFrame)
            if !restoredFrame.isEmpty {
                window.setFrame(restoredFrame, display: false)
            }
        }
        updateWindowTitle()
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

    @objc func createTextFileInActivePane(_ sender: Any?) {
        rootViewController.createTextFileInActivePane()
    }

    @objc func performNewItemActionInActivePane(_ sender: NSMenuItem) {
        guard let kind = NewItemKind(rawValue: sender.tag) else { return }
        rootViewController.performNewItemActionInActivePane(kind)
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

    @objc func copy(_ sender: Any?) {
        rootViewController.copySelectionInActivePane()
    }

    @objc func paste(_ sender: Any?) {
        rootViewController.pasteIntoActivePane()
    }

    @objc override func selectAll(_ sender: Any?) {
        rootViewController.selectAllInActivePane()
    }

    @objc func deleteSelectedItemsPermanentlyInActivePane(_ sender: Any?) {
        rootViewController.deleteSelectedItemsPermanentlyInActivePane()
    }

    @objc func revealSelectedItemsInFinderInActivePane(_ sender: Any?) {
        rootViewController.revealSelectedItemsInFinderInActivePane()
    }

    @objc func openSelectedItemsInTerminalInActivePane(_ sender: Any?) {
        rootViewController.openSelectedItemsInTerminalInActivePane()
    }

    @objc func copySelectedPathsInActivePane(_ sender: Any?) {
        rootViewController.copySelectedPathsInActivePane()
    }

    @objc func showSelectedItemsInfoInActivePane(_ sender: Any?) {
        rootViewController.showSelectedItemsInfoInActivePane()
    }

    @objc func sendSelectedItemsViaAirDropInActivePane(_ sender: Any?) {
        rootViewController.sendSelectedItemsViaAirDropInActivePane()
    }

    @objc func showShareMenuInActivePane(_ sender: Any?) {
        rootViewController.showShareMenuInActivePane(relativeTo: sender as? NSView)
    }

    func setPaneLayout(_ layout: PaneLayout) {
        rootViewController.setPaneLayout(layout)
        updateLayoutButton()
    }

    func setFileViewMode(_ mode: FileViewMode) {
        rootViewController.setFileViewModeInActivePane(mode)
        updateViewModeButton()
    }

    func workspaceSnapshot() -> Workspace? {
        guard let window else { return nil }
        return rootViewController.workspaceSnapshot(
            name: "Default",
            windowFrame: NSStringFromRect(window.frame),
            using: environment.workspaceStore
        )
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .airDrop, .share, .info, .viewMode, .paneLayout, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .airDrop, .share, .info, .flexibleSpace, .viewMode, .paneLayout]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .paneLayout {
            return makeLayoutToolbarItem(identifier: itemIdentifier)
        }
        if itemIdentifier == .viewMode {
            return makeViewModeToolbarItem(identifier: itemIdentifier)
        }
        if itemIdentifier == .airDrop {
            return makeActionToolbarItem(
                identifier: itemIdentifier,
                label: L10n.airDrop,
                image: AppIconProvider.image(.airDrop, accessibilityDescription: L10n.airDrop),
                action: #selector(sendSelectedItemsViaAirDropInActivePane(_:))
            )
        }
        if itemIdentifier == .share {
            return makeActionToolbarItem(
                identifier: itemIdentifier,
                label: L10n.share,
                image: AppIconProvider.image(.share, accessibilityDescription: L10n.share),
                action: #selector(showShareMenuInActivePane(_:))
            )
        }
        if itemIdentifier == .info {
            return makeActionToolbarItem(
                identifier: itemIdentifier,
                label: L10n.showInfo,
                image: AppIconProvider.image(.info, accessibilityDescription: L10n.showInfo),
                action: #selector(showSelectedItemsInfoInActivePane(_:))
            )
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

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(refreshActivePane(_:)),
             #selector(focusActivePathInput(_:)),
             #selector(createFolderInActivePane(_:)),
             #selector(createTextFileInActivePane(_:)),
             #selector(performNewItemActionInActivePane(_:)),
             #selector(showLayoutPicker(_:)),
             #selector(toggleViewMode(_:)):
            return true
        case #selector(renameSelectedItemInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.renameSelectedItem(_:)))
        case #selector(copySelectedItemsInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.copySelectedItems(_:)))
        case #selector(moveSelectedItemsInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.moveSelectedItems(_:)))
        case #selector(trashSelectedItemsInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.trashSelectedItems(_:)))
        case #selector(deleteSelectedItemsPermanentlyInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.deleteSelectedItemsPermanently(_:)))
        case #selector(revealSelectedItemsInFinderInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.revealSelectedItemsInFinder(_:)))
        case #selector(openSelectedItemsInTerminalInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.openSelectedItemsInTerminal(_:)))
        case #selector(copySelectedPathsInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.copySelectedItemPaths(_:)))
        case #selector(showSelectedItemsInfoInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.showSelectedItemsInfo(_:)))
        case #selector(sendSelectedItemsViaAirDropInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.sendSelectedItemsViaAirDrop(_:)))
        case #selector(showShareMenuInActivePane(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.showShareMenuProxy(_:)))
        case #selector(copy(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.copySelectionToPasteboard(_:)))
        case #selector(paste(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.pasteFromPasteboard(_:)))
        case #selector(selectAll(_:)):
            return rootViewController.canPerformFileAction(#selector(FilePaneViewController.selectAllItems(_:)))
        default:
            guard let action = item.action else { return true }
            return rootViewController.canPerformFileAction(action)
        }
    }

    private func makeLayoutToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L10n.layout
        item.paletteLabel = L10n.layout
        let button = makeToolbarIconButton(action: #selector(showLayoutPicker(_:)))
        item.view = button
        layoutToolbarItem = item
        layoutToolbarButton = button
        updateLayoutButton()
        return item
    }

    private func makeViewModeToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = L10n.view
        item.paletteLabel = L10n.view
        let button = makeToolbarIconButton(action: #selector(toggleViewMode(_:)))
        item.view = button
        viewModeToolbarItem = item
        viewModeToolbarButton = button
        updateViewModeButton()
        return item
    }

    private func makeActionToolbarItem(identifier: NSToolbarItem.Identifier, label: String, image: NSImage?, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        let button = makeToolbarIconButton(action: action)
        button.image = image
        button.toolTip = label
        button.setAccessibilityLabel(label)
        item.view = button
        item.target = self
        item.action = action
        return item
    }

    private func updateLayoutButton() {
        let layout = rootViewController.currentPaneLayout
        layoutToolbarItem?.image = layout.toolbarImage
        layoutToolbarItem?.label = L10n.layout
        layoutToolbarItem?.paletteLabel = L10n.layout
        layoutToolbarItem?.toolTip = layout.displayName
        layoutToolbarButton?.image = layout.toolbarImage
        layoutToolbarButton?.toolTip = layout.displayName
        layoutToolbarButton?.setAccessibilityLabel(layout.displayName)
    }

    private func updateViewModeButton() {
        let mode = rootViewController.currentFileViewMode
        let title = mode == .list ? L10n.viewModeList : L10n.viewModeGrid
        viewModeToolbarItem?.image = viewModeImage
        viewModeToolbarItem?.label = L10n.view
        viewModeToolbarItem?.paletteLabel = L10n.view
        viewModeToolbarItem?.toolTip = title
        viewModeToolbarButton?.image = viewModeImage
        viewModeToolbarButton?.toolTip = title
        viewModeToolbarButton?.setAccessibilityLabel(title)
    }

    private func updateWindowTitle() {
        guard let window else { return }
        guard let url = rootViewController.activePaneURL else {
            window.title = "Clover"
            return
        }
        let name = FileManager.default.displayName(atPath: url.path)
        window.title = name.isEmpty ? url.lastPathComponent : name
    }

    private var viewModeImage: NSImage? {
        let symbol: AppSymbol = rootViewController.currentFileViewMode == .list ? .list : .grid
        return AppIconProvider.image(symbol, accessibilityDescription: nil)
    }

    @objc private func toggleViewMode(_ sender: Any?) {
        let nextMode: FileViewMode = rootViewController.currentFileViewMode == .list ? .grid : .list
        setFileViewMode(nextMode)
    }

    private func makeToolbarIconButton(action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(), target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
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
        let anchorView = (sender as? NSView) ?? layoutToolbarButton
        if let anchorView {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        }
    }
}

private extension NSToolbarItem.Identifier {
    static let refresh = NSToolbarItem.Identifier("CloverToolbar.Refresh")
    static let airDrop = NSToolbarItem.Identifier("CloverToolbar.AirDrop")
    static let share = NSToolbarItem.Identifier("CloverToolbar.Share")
    static let info = NSToolbarItem.Identifier("CloverToolbar.Info")
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
