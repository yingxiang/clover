import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
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
            showMainWindow()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    private func showMainWindow() {
        let controller = mainWindowController ?? MainWindowController(environment: environment)
        mainWindowController = controller
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
        appMenu.addItem(NSMenuItem(title: "Quit Clover", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newFolderItem = NSMenuItem(title: "New Folder", action: #selector(createFolderInActivePane(_:)), keyEquivalent: "n")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        newFolderItem.target = self
        fileMenu.addItem(newFolderItem)
        fileMenu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshActivePane(_:)), keyEquivalent: "r")
        refreshItem.target = self
        fileMenu.addItem(refreshItem)
        let focusPathItem = NSMenuItem(title: "Go to Folder", action: #selector(focusActivePathInput(_:)), keyEquivalent: "l")
        focusPathItem.target = self
        fileMenu.addItem(focusPathItem)
        fileMenu.addItem(.separator())
        let renameItem = NSMenuItem(title: "Rename", action: #selector(renameSelectedItemInActivePane(_:)), keyEquivalent: "\r")
        renameItem.target = self
        fileMenu.addItem(renameItem)
        let copyToItem = NSMenuItem(title: "Copy To...", action: #selector(copySelectedItemsInActivePane(_:)), keyEquivalent: "c")
        copyToItem.keyEquivalentModifierMask = [.command, .option]
        copyToItem.target = self
        fileMenu.addItem(copyToItem)
        let moveToItem = NSMenuItem(title: "Move To...", action: #selector(moveSelectedItemsInActivePane(_:)), keyEquivalent: "m")
        moveToItem.keyEquivalentModifierMask = [.command, .option]
        moveToItem.target = self
        fileMenu.addItem(moveToItem)
        let trashItem = NSMenuItem(title: "Move to Trash", action: #selector(trashSelectedItemsInActivePane(_:)), keyEquivalent: "\u{8}")
        trashItem.target = self
        fileMenu.addItem(trashItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        addLayoutItem(title: "Single Pane", key: "1", layout: .single, to: viewMenu)
        addLayoutItem(title: "Two Panes Vertical", key: "2", layout: .twoVertical, to: viewMenu)
        addLayoutItem(title: "Two Panes Horizontal", key: "3", layout: .twoHorizontal, to: viewMenu)
        addLayoutItem(title: "Four Panes", key: "4", layout: .fourGrid, to: viewMenu)
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

    @objc private func refreshActivePane(_ sender: Any?) {
        mainWindowController?.refreshActivePane(sender)
    }

    @objc private func focusActivePathInput(_ sender: Any?) {
        mainWindowController?.focusActivePathInput(sender)
    }

    @objc private func createFolderInActivePane(_ sender: Any?) {
        mainWindowController?.createFolderInActivePane(sender)
    }

    @objc private func renameSelectedItemInActivePane(_ sender: Any?) {
        mainWindowController?.renameSelectedItemInActivePane(sender)
    }

    @objc private func copySelectedItemsInActivePane(_ sender: Any?) {
        mainWindowController?.copySelectedItemsInActivePane(sender)
    }

    @objc private func moveSelectedItemsInActivePane(_ sender: Any?) {
        mainWindowController?.moveSelectedItemsInActivePane(sender)
    }

    @objc private func trashSelectedItemsInActivePane(_ sender: Any?) {
        mainWindowController?.trashSelectedItemsInActivePane(sender)
    }

    @objc private func changePaneLayout(_ sender: NSMenuItem) {
        guard let layout = PaneLayout(menuTag: sender.tag) else { return }
        mainWindowController?.setPaneLayout(layout)
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
