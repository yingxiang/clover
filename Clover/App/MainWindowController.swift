import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSUserInterfaceValidations {
    private let rootViewController: RootSplitViewController
    private weak var layoutToolbarItem: NSToolbarItem?
    private weak var layoutToolbarButton: NSButton?
    private weak var viewModeToolbarItem: NSToolbarItem?
    private weak var viewModeToolbarButton: NSButton?
    private weak var airDropToolbarButton: NSButton?
    private weak var shareToolbarButton: NSButton?
    private weak var infoToolbarButton: NSButton?
    private weak var airDropToolbarItem: NSToolbarItem?
    private weak var shareToolbarItem: NSToolbarItem?
    private weak var infoToolbarItem: NSToolbarItem?
    private weak var sidebarTitlebarButton: NSButton?
    private var sidebarTitlebarAccessory: NSTitlebarAccessoryViewController?
    private var layoutPopover: NSPopover?
    private var upgradeProWindowController: UpgradeProWindowController?
    private var toolbarContextMenuMonitor: Any?
    private var paneSwitchKeyMonitor: Any?
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
        window.title = String(localized: "app_name", defaultValue: "Clover")
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
        rootViewController.commandAvailabilityChangeHandler = { [weak self] in
            self?.updateToolbarButtonAvailability()
        }

        let toolbar = NSToolbar(identifier: "CloverToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        installSidebarTitlebarButton()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        installToolbarContextMenuBlocker()
        installPaneSwitchKeyMonitor()

        if let restoredWorkspace {
            rootViewController.loadViewIfNeeded()
            rootViewController.restore(from: restoredWorkspace)
            let restoredFrame = NSRectFromString(restoredWorkspace.windowFrame)
            if !restoredFrame.isEmpty {
                window.setFrame(restoredFrame, display: false)
            }
            updateLayoutButton()
            updateViewModeButton()
            updateSidebarTitlebarButton()
            updateToolbarButtonAvailability()
        }
        updateWindowTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func refreshActivePane(_ sender: Any?) {
        rootViewController.refreshActivePane()
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        if let toolbarContextMenuMonitor {
            NSEvent.removeMonitor(toolbarContextMenuMonitor)
            self.toolbarContextMenuMonitor = nil
        }
        if let paneSwitchKeyMonitor {
            NSEvent.removeMonitor(paneSwitchKeyMonitor)
            self.paneSwitchKeyMonitor = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: notification.object)
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

    @objc private func toggleSidebar(_ sender: Any?) {
        rootViewController.toggleSidebar()
        updateSidebarTitlebarButton()
    }

    func setPaneLayout(_ layout: PaneLayout) {
        guard ensurePaneLayoutAccess(layout) else { return }
        rootViewController.setPaneLayout(layout)
        updateLayoutButton()
        updateToolbarButtonAvailability()
    }

    func setFileViewMode(_ mode: FileViewMode) {
        rootViewController.setFileViewModeInActivePane(mode)
        updateViewModeButton()
    }

    func openInActivePane(_ url: URL) {
        rootViewController.openInActivePane(url)
        updateWindowTitle()
    }

    func activateNextPane() {
        rootViewController.activateNextPane()
    }

    func activatePreviousPane() {
        rootViewController.activatePreviousPane()
    }

    func workspaceSnapshot() -> Workspace? {
        guard let window else { return nil }
        return rootViewController.workspaceSnapshot(
            name: "Default",
            windowFrame: NSStringFromRect(window.frame),
            using: environment.workspaceStore
        )
    }

    func saveWorkspace(named name: String) throws -> Workspace? {
        guard let snapshot = workspaceSnapshot() else { return nil }
        return try environment.workspaceStore.saveWorkspace(snapshot, named: name)
    }

    func savedWorkspaces() throws -> [Workspace] {
        try environment.workspaceStore.loadSavedWorkspaces()
    }

    func restoreWorkspace(_ workspace: Workspace) {
        rootViewController.restoreWorkspace(workspace)
        updateLayoutButton()
        updateViewModeButton()
        updateSidebarTitlebarButton()
        updateToolbarButtonAvailability()
        updateWindowTitle()
    }

    func activePaneSelectedURLs() -> [URL] {
        rootViewController.activePaneSelectedURLs()
    }

    var activePaneURL: URL? {
        rootViewController.activePaneURL
    }

    func paneURLs() -> [URL] {
        rootViewController.paneURLs()
    }

    func reloadToolbarConfiguration() {
        guard let window else { return }
        let toolbar = NSToolbar(identifier: "CloverToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        updateLayoutButton()
        updateViewModeButton()
        updateToolbarButtonAvailability()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .terminal, .airDrop, .share, .info, .viewMode, .paneLayout, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = []
        let prefs = environment.toolbarPreferencesStore
        if prefs.isVisible(.refresh) { identifiers.append(.refresh) }
        if prefs.isVisible(.terminal) { identifiers.append(.terminal) }
        if prefs.isVisible(.airDrop) { identifiers.append(.airDrop) }
        if prefs.isVisible(.share) { identifiers.append(.share) }
        if prefs.isVisible(.info) { identifiers.append(.info) }
        identifiers.append(.flexibleSpace)
        if prefs.isVisible(.viewMode) { identifiers.append(.viewMode) }
        if prefs.isVisible(.paneLayout) { identifiers.append(.paneLayout) }
        return identifiers
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
                label: String(localized: "airdrop", defaultValue: "AirDrop"),
                image: AppIconProvider.image(.airDrop, accessibilityDescription: String(localized: "airdrop", defaultValue: "AirDrop")),
                action: #selector(sendSelectedItemsViaAirDropInActivePane(_:))
            )
        }
        if itemIdentifier == .terminal {
            return makeActionToolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "open_in_terminal", defaultValue: "Open in Terminal"),
                image: AppIconProvider.image(.terminal, accessibilityDescription: String(localized: "open_in_terminal", defaultValue: "Open in Terminal")),
                action: #selector(openSelectedItemsInTerminalInActivePane(_:))
            )
        }
        if itemIdentifier == .share {
            return makeActionToolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "share", defaultValue: "Share"),
                image: AppIconProvider.image(.share, accessibilityDescription: String(localized: "share", defaultValue: "Share")),
                action: #selector(showShareMenuInActivePane(_:))
            )
        }
        if itemIdentifier == .info {
            return makeActionToolbarItem(
                identifier: itemIdentifier,
                label: String(localized: "show_info", defaultValue: "Get Info"),
                image: AppIconProvider.image(.info, accessibilityDescription: String(localized: "show_info", defaultValue: "Get Info")),
                action: #selector(showSelectedItemsInfoInActivePane(_:))
            )
        }
        guard itemIdentifier == .refresh else { return nil }
        return makeActionToolbarItem(
            identifier: itemIdentifier,
            label: String(localized: "refresh", defaultValue: "Refresh"),
            image: AppIconProvider.image(.refresh, accessibilityDescription: String(localized: "refresh", defaultValue: "Refresh")),
            action: #selector(refreshActivePane(_:))
        )
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
        item.label = String(localized: "layout", defaultValue: "Layout")
        item.paletteLabel = String(localized: "layout", defaultValue: "Layout")
        let button = makeToolbarIconButton(action: #selector(showLayoutPicker(_:)))
        item.view = button
        layoutToolbarItem = item
        layoutToolbarButton = button
        updateLayoutButton()
        return item
    }

    private func makeViewModeToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = String(localized: "view", defaultValue: "View")
        item.paletteLabel = String(localized: "view", defaultValue: "View")
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
        switch identifier {
        case .airDrop:
            airDropToolbarItem = item
            airDropToolbarButton = button
        case .share:
            shareToolbarItem = item
            shareToolbarButton = button
        case .info:
            infoToolbarItem = item
            infoToolbarButton = button
        default:
            break
        }
        updateToolbarButtonAvailability()
        return item
    }

    private func updateLayoutButton() {
        let layout = rootViewController.currentPaneLayout
        layoutToolbarItem?.image = layout.toolbarImage
        layoutToolbarItem?.label = String(localized: "layout", defaultValue: "Layout")
        layoutToolbarItem?.paletteLabel = String(localized: "layout", defaultValue: "Layout")
        layoutToolbarItem?.toolTip = String(localized: "layout", defaultValue: "Layout")
        layoutToolbarButton?.image = layout.toolbarImage
        layoutToolbarButton?.toolTip = String(localized: "layout", defaultValue: "Layout")
        layoutToolbarButton?.setAccessibilityLabel(String(localized: "layout", defaultValue: "Layout"))
    }

    private func updateViewModeButton() {
        viewModeToolbarItem?.image = viewModeImage
        viewModeToolbarItem?.label = String(localized: "view", defaultValue: "View")
        viewModeToolbarItem?.paletteLabel = String(localized: "view", defaultValue: "View")
        viewModeToolbarItem?.toolTip = String(localized: "view", defaultValue: "View")
        viewModeToolbarButton?.image = viewModeImage
        viewModeToolbarButton?.toolTip = String(localized: "view", defaultValue: "View")
        viewModeToolbarButton?.setAccessibilityLabel(String(localized: "view", defaultValue: "View"))
    }

    private func updateToolbarButtonAvailability() {
        let airDropEnabled = rootViewController.canPerformFileAction(#selector(FilePaneViewController.sendSelectedItemsViaAirDrop(_:)))
        airDropToolbarItem?.isEnabled = airDropEnabled
        airDropToolbarButton?.isEnabled = airDropEnabled

        let shareEnabled = rootViewController.canPerformFileAction(#selector(FilePaneViewController.showShareMenuProxy(_:)))
        shareToolbarItem?.isEnabled = shareEnabled
        shareToolbarButton?.isEnabled = shareEnabled

        let infoEnabled = rootViewController.canPerformFileAction(#selector(FilePaneViewController.showSelectedItemsInfo(_:)))
        infoToolbarItem?.isEnabled = infoEnabled
        infoToolbarButton?.isEnabled = infoEnabled
    }

    private func updateSidebarTitlebarButton() {
        let isCollapsed = rootViewController.isSidebarCollapsed
        let title = isCollapsed ? String(localized: "show_sidebar", defaultValue: "Show Sidebar") : String(localized: "hide_sidebar", defaultValue: "Hide Sidebar")
        sidebarTitlebarButton?.toolTip = title
        sidebarTitlebarButton?.setAccessibilityLabel(title)
    }

    private func updateWindowTitle() {
        guard let window else { return }
        guard let url = rootViewController.activePaneURL else {
            window.title = String(localized: "app_name", defaultValue: "Clover")
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

    private func installSidebarTitlebarButton() {
        guard let window else { return }

        let image = AppIconProvider.image(.sidebar, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        let button = NSButton(image: image, target: self, action: #selector(toggleSidebar(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 56, height: 52))
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        accessoryView.addSubview(button)
        NSLayoutConstraint.activate([
            accessoryView.widthAnchor.constraint(equalToConstant: 56),
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 28),
            button.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            button.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = accessoryView
        accessory.layoutAttribute = .left
        window.addTitlebarAccessoryViewController(accessory)

        sidebarTitlebarButton = button
        sidebarTitlebarAccessory = accessory
        updateSidebarTitlebarButton()
    }

    private func installToolbarContextMenuBlocker() {
        toolbarContextMenuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, self.shouldBlockToolbarContextMenu(event) else { return event }
            self.window?.toolbar?.displayMode = .iconOnly
            return nil
        }
    }

    private func shouldBlockToolbarContextMenu(_ event: NSEvent) -> Bool {
        guard let window,
              window.toolbar != nil,
              event.type == .rightMouseDown || event.type == .rightMouseUp || ((event.type == .leftMouseDown || event.type == .leftMouseUp) && event.modifierFlags.contains(.control)) else {
            return false
        }

        if event.window === window {
            return titlebarOrToolbarContains(event.locationInWindow, in: window)
        }

        guard window.styleMask.contains(.fullScreen) else { return false }
        if eventWindowLooksLikeSystemChrome(event.window) {
            return true
        }
        guard let eventWindow = event.window else { return false }
        let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
        guard let screen = window.screen ?? eventWindow.screen else { return false }
        return screen.frame.maxY - screenPoint.y <= 96
    }

    private func titlebarOrToolbarContains(_ pointInWindow: NSPoint, in window: NSWindow) -> Bool {
        let chromeMinY = window.contentLayoutRect.maxY
        let chromeHeight = max(0, window.frame.height - chromeMinY)
        if chromeHeight > 0 {
            return NSRect(x: 0, y: chromeMinY, width: window.frame.width, height: chromeHeight).contains(pointInWindow)
        }

        guard window.styleMask.contains(.fullScreen) else { return false }
        return NSRect(x: 0, y: max(0, window.frame.height - 96), width: window.frame.width, height: 96).contains(pointInWindow)
    }

    private func eventWindowLooksLikeSystemChrome(_ eventWindow: NSWindow?) -> Bool {
        guard let eventWindow else { return false }
        var names = [String(describing: type(of: eventWindow))]
        var view = eventWindow.contentView
        while let current = view {
            names.append(String(describing: type(of: current)))
            view = current.superview
        }
        return names.contains { name in
            name.localizedCaseInsensitiveContains("toolbar") ||
            name.localizedCaseInsensitiveContains("titlebar")
        }
    }

    private func installPaneSwitchKeyMonitor() {
        paneSwitchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.shouldSwitchPane(for: event) else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) {
                self.activatePreviousPane()
            } else {
                self.activateNextPane()
            }
            return nil
        }
    }

    private func shouldSwitchPane(for event: NSEvent) -> Bool {
        guard event.window === window,
              event.keyCode == 48,
              event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.shift, .numericPad, .function])
                .isEmpty,
              !isEditingText else {
            return false
        }
        return rootViewController.canActivateAdjacentPane
    }

    private var isEditingText: Bool {
        guard let firstResponder = window?.firstResponder else { return false }
        if firstResponder is NSTextView {
            return true
        }
        if let control = firstResponder as? NSControl,
           control.currentEditor() != nil {
            return true
        }
        return false
    }

    @objc private func showLayoutPicker(_ sender: Any?) {
        let controller = LayoutPickerViewController(selectedLayout: rootViewController.currentPaneLayout)
        controller.selectionHandler = { [weak self] layout in
            self?.layoutPopover?.close()
            self?.setPaneLayout(layout)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 174, height: 164)
        popover.contentViewController = controller
        layoutPopover = popover
        let anchorView = (sender as? NSView) ?? layoutToolbarButton
        if let anchorView {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        }
    }

    private func ensurePaneLayoutAccess(_ layout: PaneLayout) -> Bool {
        guard !layout.isProOnly || environment.featureGate.canUse(.advancedPaneLayouts) else {
            showUpgradeProWindow()
            return false
        }
        return true
    }

    private func showUpgradeProWindow() {
        let controller = upgradeProWindowController ?? UpgradeProWindowController(entitlementService: environment.entitlementService)
        upgradeProWindowController = controller
        controller.showWindow(self)
    }
}

private extension NSToolbarItem.Identifier {
    static let refresh = NSToolbarItem.Identifier("CloverToolbar.Refresh")
    static let terminal = NSToolbarItem.Identifier("CloverToolbar.Terminal")
    static let airDrop = NSToolbarItem.Identifier("CloverToolbar.AirDrop")
    static let share = NSToolbarItem.Identifier("CloverToolbar.Share")
    static let info = NSToolbarItem.Identifier("CloverToolbar.Info")
    static let viewMode = NSToolbarItem.Identifier("CloverToolbar.ViewMode")
    static let paneLayout = NSToolbarItem.Identifier("CloverToolbar.PaneLayout")
}
