import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [MainWindowController] = []
    private let environment = AppEnvironment.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow(reuseExisting: true)
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    private func showMainWindow(reuseExisting: Bool = false) {
        windowControllers.removeAll { $0.window == nil }
        let controller: MainWindowController
        if reuseExisting, let existing = windowControllers.first {
            controller = existing
        } else {
            let restoredWorkspace = try? environment.workspaceStore.loadDefaultWorkspace()
            controller = MainWindowController(environment: environment, restoredWorkspace: restoredWorkspace)
            controller.window?.delegate = self
            windowControllers.append(controller)
        }
        controller.showWindow(self)
        guard let window = controller.window else { return }
        if let screen = NSScreen.main, !screen.visibleFrame.intersects(window.frame) {
            window.center()
        }
        window.deminiaturize(self)
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Clover")
        let quitItem = NSMenuItem(title: L10n.quitClover, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.file)
        let newWindowItem = makeMenuItem(title: L10n.newWindow, action: #selector(newWindow(_:)), keyEquivalent: "n", target: self)
        newWindowItem.image = AppIconProvider.image(.open, accessibilityDescription: L10n.newWindow)
        fileMenu.addItem(newWindowItem)
        fileMenu.addItem(.separator())
        let newItem = NSMenuItem(title: L10n.new, action: nil, keyEquivalent: "")
        newItem.image = AppIconProvider.menuImage(.folderPlus, accessibilityDescription: L10n.new)
        newItem.submenu = makeNewMenu()
        fileMenu.addItem(newItem)
        fileMenu.addItem(.separator())
        let refreshItem = makeMenuItem(title: L10n.refresh, action: #selector(refreshActivePane(_:)), keyEquivalent: "r", target: self)
        refreshItem.image = AppIconProvider.image(.refresh, accessibilityDescription: L10n.refresh)
        fileMenu.addItem(refreshItem)
        let focusPathItem = makeMenuItem(title: L10n.goToFolder, action: #selector(focusActivePathInput(_:)), keyEquivalent: "l", target: self)
        focusPathItem.image = AppIconProvider.image(.folder, accessibilityDescription: L10n.goToFolder)
        fileMenu.addItem(focusPathItem)
        fileMenu.addItem(.separator())
        let renameItem = makeMenuItem(title: L10n.rename, action: #selector(renameSelectedItemInActivePane(_:)), keyEquivalent: "\r", target: self)
        renameItem.image = AppIconProvider.image(.rename, accessibilityDescription: L10n.rename)
        fileMenu.addItem(renameItem)
        let copyItem = makeMenuItem(title: L10n.copy, action: #selector(MainWindowController.copy(_:)), keyEquivalent: "c")
        copyItem.image = AppIconProvider.image(.copy, accessibilityDescription: L10n.copy)
        fileMenu.addItem(copyItem)
        let pasteItem = makeMenuItem(title: L10n.paste, action: #selector(MainWindowController.paste(_:)), keyEquivalent: "v")
        pasteItem.image = AppIconProvider.image(.paste, accessibilityDescription: L10n.paste)
        fileMenu.addItem(pasteItem)
        let copyToItem = makeMenuItem(title: L10n.copyTo, action: #selector(copySelectedItemsInActivePane(_:)), keyEquivalent: "c", target: self)
        copyToItem.keyEquivalentModifierMask = [.command, .option]
        copyToItem.image = AppIconProvider.image(.copy, accessibilityDescription: L10n.copyTo)
        fileMenu.addItem(copyToItem)
        let moveToItem = makeMenuItem(title: L10n.moveTo, action: #selector(moveSelectedItemsInActivePane(_:)), keyEquivalent: "m", target: self)
        moveToItem.keyEquivalentModifierMask = [.command, .option]
        moveToItem.image = AppIconProvider.image(.move, accessibilityDescription: L10n.moveTo)
        fileMenu.addItem(moveToItem)
        let trashItem = makeMenuItem(title: L10n.moveToTrash, action: #selector(trashSelectedItemsInActivePane(_:)), keyEquivalent: "\u{8}", target: self)
        trashItem.image = AppIconProvider.image(.trash, accessibilityDescription: L10n.moveToTrash)
        fileMenu.addItem(trashItem)
        fileMenu.addItem(.separator())
        let selectAllItem = makeMenuItem(title: L10n.selectAll, action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.image = AppIconProvider.image(.selectAll, accessibilityDescription: L10n.selectAll)
        fileMenu.addItem(selectAllItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: L10n.view)
        addViewModeItem(title: L10n.viewModeList, key: "0", mode: .list, to: viewMenu)
        addViewModeItem(title: L10n.viewModeGrid, key: "9", mode: .grid, to: viewMenu)
        viewMenu.addItem(.separator())
        addLayoutItem(title: L10n.singlePane, key: "1", layout: .single, to: viewMenu)
        addLayoutItem(title: L10n.twoPanesVertical, key: "2", layout: .twoVertical, to: viewMenu)
        addLayoutItem(title: L10n.twoPanesHorizontal, key: "3", layout: .twoHorizontal, to: viewMenu)
        addLayoutItem(title: L10n.fourPanes, key: "4", layout: .fourGrid, to: viewMenu)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }

    private func addLayoutItem(title: String, key: String, layout: PaneLayout, to menu: NSMenu) {
        let item = makeMenuItem(title: title, action: #selector(changePaneLayout(_:)), keyEquivalent: key, target: self)
        item.tag = layout.menuTag
        item.image = AppIconProvider.image(.layoutSplit, accessibilityDescription: title)
        menu.addItem(item)
    }

    private func addViewModeItem(title: String, key: String, mode: FileViewMode, to menu: NSMenu) {
        let item = makeMenuItem(title: title, action: #selector(changeFileViewMode(_:)), keyEquivalent: key, target: self)
        item.tag = mode.menuTag
        item.image = AppIconProvider.image(mode == .list ? .list : .grid, accessibilityDescription: title)
        menu.addItem(item)
    }

    private func makeNewMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.new)
        for kind in NewItemKind.allCases where kind.isAvailable {
            let item = makeMenuItem(title: kind.title, action: #selector(performNewItemActionInActivePane(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            if kind == .folder {
                item.keyEquivalent = "n"
                item.keyEquivalentModifierMask = [.command, .shift]
            }
            item.image = kind.appURL.map { AppIconProvider.menuFileImage($0.path, accessibilityDescription: kind.title) }
                ?? AppIconProvider.menuImage(kind.symbol, accessibilityDescription: kind.title)
            menu.addItem(item)
        }
        return menu
    }

    private func makeMenuItem(title: String, action: Selector?, keyEquivalent: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    @objc private func newWindow(_ sender: Any?) {
        showMainWindow()
    }

    @objc private func refreshActivePane(_ sender: Any?) {
        keyWindowController?.refreshActivePane(sender)
    }

    @objc private func focusActivePathInput(_ sender: Any?) {
        keyWindowController?.focusActivePathInput(sender)
    }

    @objc private func createFolderInActivePane(_ sender: Any?) {
        keyWindowController?.createFolderInActivePane(sender)
    }

    @objc private func createTextFileInActivePane(_ sender: Any?) {
        keyWindowController?.createTextFileInActivePane(sender)
    }

    @objc private func renameSelectedItemInActivePane(_ sender: Any?) {
        keyWindowController?.renameSelectedItemInActivePane(sender)
    }

    @objc private func performNewItemActionInActivePane(_ sender: NSMenuItem) {
        keyWindowController?.performNewItemActionInActivePane(sender)
    }

    @objc private func copySelectedItemsInActivePane(_ sender: Any?) {
        keyWindowController?.copySelectedItemsInActivePane(sender)
    }

    @objc private func moveSelectedItemsInActivePane(_ sender: Any?) {
        keyWindowController?.moveSelectedItemsInActivePane(sender)
    }

    @objc private func trashSelectedItemsInActivePane(_ sender: Any?) {
        keyWindowController?.trashSelectedItemsInActivePane(sender)
    }

    @objc private func changePaneLayout(_ sender: NSMenuItem) {
        guard let layout = PaneLayout(menuTag: sender.tag) else { return }
        keyWindowController?.setPaneLayout(layout)
    }

    @objc private func changeFileViewMode(_ sender: NSMenuItem) {
        guard let mode = FileViewMode(menuTag: sender.tag) else { return }
        keyWindowController?.setFileViewMode(mode)
    }

    private var keyWindowController: MainWindowController? {
        if let keyWindow = NSApp.keyWindow,
           let controller = windowControllers.first(where: { $0.window === keyWindow }) {
            return controller
        }
        return windowControllers.last
    }
}

extension AppDelegate: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(changePaneLayout(_:)),
             #selector(changeFileViewMode(_:)),
             #selector(performNewItemActionInActivePane(_:)),
             #selector(newWindow(_:)):
            return true
        default:
            return keyWindowController?.validateUserInterfaceItem(item) ?? false
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let controller = windowControllers.first(where: { $0.window === window }) {
            saveWorkspace(from: controller)
        }
        windowControllers.removeAll { $0.window === window }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowControllers.forEach(saveWorkspace(from:))
    }

    private func saveWorkspace(from controller: MainWindowController) {
        guard let workspace = controller.workspaceSnapshot() else { return }
        do {
            try environment.workspaceStore.saveDefaultWorkspace(workspace)
        } catch {
            Logger.workspace.error("Failed to save workspace: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension PaneLayout {
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

private extension FileViewMode {
    var menuTag: Int {
        switch self {
        case .list:
            return 1
        case .grid:
            return 2
        }
    }

    init?(menuTag: Int) {
        switch menuTag {
        case 1:
            self = .list
        case 2:
            self = .grid
        default:
            return nil
        }
    }
}
