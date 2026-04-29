import AppKit

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
            controller = MainWindowController(environment: environment)
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
        appMenu.addItem(NSMenuItem(title: L10n.quitClover, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.file)
        let newWindowItem = NSMenuItem(title: L10n.newWindow, action: #selector(newWindow(_:)), keyEquivalent: "n")
        newWindowItem.target = self
        fileMenu.addItem(newWindowItem)
        fileMenu.addItem(.separator())
        let newFolderItem = NSMenuItem(title: L10n.newFolder, action: #selector(createFolderInActivePane(_:)), keyEquivalent: "n")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        newFolderItem.target = self
        fileMenu.addItem(newFolderItem)
        fileMenu.addItem(.separator())
        let refreshItem = NSMenuItem(title: L10n.refresh, action: #selector(refreshActivePane(_:)), keyEquivalent: "r")
        refreshItem.target = self
        fileMenu.addItem(refreshItem)
        let focusPathItem = NSMenuItem(title: L10n.goToFolder, action: #selector(focusActivePathInput(_:)), keyEquivalent: "l")
        focusPathItem.target = self
        fileMenu.addItem(focusPathItem)
        fileMenu.addItem(.separator())
        let renameItem = NSMenuItem(title: L10n.rename, action: #selector(renameSelectedItemInActivePane(_:)), keyEquivalent: "\r")
        renameItem.target = self
        fileMenu.addItem(renameItem)
        let copyToItem = NSMenuItem(title: L10n.copyTo, action: #selector(copySelectedItemsInActivePane(_:)), keyEquivalent: "c")
        copyToItem.keyEquivalentModifierMask = [.command, .option]
        copyToItem.target = self
        fileMenu.addItem(copyToItem)
        let moveToItem = NSMenuItem(title: L10n.moveTo, action: #selector(moveSelectedItemsInActivePane(_:)), keyEquivalent: "m")
        moveToItem.keyEquivalentModifierMask = [.command, .option]
        moveToItem.target = self
        fileMenu.addItem(moveToItem)
        let trashItem = NSMenuItem(title: L10n.moveToTrash, action: #selector(trashSelectedItemsInActivePane(_:)), keyEquivalent: "\u{8}")
        trashItem.target = self
        fileMenu.addItem(trashItem)
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
        let item = NSMenuItem(title: title, action: #selector(changePaneLayout(_:)), keyEquivalent: key)
        item.target = self
        item.tag = layout.menuTag
        menu.addItem(item)
    }

    private func addViewModeItem(title: String, key: String, mode: FileViewMode, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(changeFileViewMode(_:)), keyEquivalent: key)
        item.target = self
        item.tag = mode.menuTag
        menu.addItem(item)
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

    @objc private func renameSelectedItemInActivePane(_ sender: Any?) {
        keyWindowController?.renameSelectedItemInActivePane(sender)
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windowControllers.removeAll { $0.window === window }
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
