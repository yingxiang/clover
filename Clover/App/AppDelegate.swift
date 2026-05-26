import AppKit
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [MainWindowController] = []
    private var supportDeveloperWindowController: SupportDeveloperWindowController?
    private var upgradeProWindowController: UpgradeProWindowController?
    private var proWorkspacesWindowController: ProWorkspacesWindowController?
    private var proStashShelfWindowController: ProStashShelfWindowController?
    private var proBatchRenameWindowController: ProBatchRenameWindowController?
    private var proFolderCompareWindowController: ProFolderCompareWindowController?
    private var proPreferencesWindowController: ProPreferencesWindowController?
    private var appUpgradeProMenuItem: NSMenuItem?
    private var proUpgradeMenuItem: NSMenuItem?
    private var entitlementCancellable: AnyCancellable?
    private let environment = AppEnvironment.live()
    private let omniCaptureAppStoreURL = URL(string: "macappstore://apps.apple.com/us/app/omni-capture/id6760931624")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.disableRelaunchOnLogin()
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        observeEntitlements()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    @discardableResult
    func showMainWindow(reuseExisting: Bool = false) -> MainWindowController {
        windowControllers.removeAll { $0.window == nil }
        let controller: MainWindowController
        if reuseExisting, let existing = windowControllers.first {
            controller = existing
        } else {
            let restoredWorkspace = environment.directoryAccessStore.hasSavedAccess(to: UserDirectories.homeURL)
                ? try? environment.workspaceStore.loadDefaultWorkspace()
                : nil
            controller = MainWindowController(environment: environment, restoredWorkspace: restoredWorkspace)
            controller.window?.delegate = self
            windowControllers.append(controller)
        }
        controller.showWindow(self)
        bringWindowToFront(controller)
        return controller
    }

    @MainActor
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: L10n.appName)
        let screenshotItem = NSMenuItem(title: L10n.screenshot, action: #selector(openOmniCaptureInAppStore(_:)), keyEquivalent: "")
        screenshotItem.target = self
        screenshotItem.image = AppIconProvider.menuImage(.screenshot, accessibilityDescription: L10n.screenshot)
        appMenu.addItem(screenshotItem)
        let upgradeProItem = NSMenuItem(title: L10n.upgradeToPro, action: #selector(showUpgradeProWindow(_:)), keyEquivalent: "")
        upgradeProItem.target = self
        upgradeProItem.image = AppIconProvider.menuImage(.pro, accessibilityDescription: L10n.upgradeToPro)
        appUpgradeProMenuItem = upgradeProItem
        appMenu.addItem(upgradeProItem)
#if DEBUG
        let manageSubscriptionItem = NSMenuItem(title: L10n.manageSubscription, action: #selector(manageSubscription(_:)), keyEquivalent: "")
        manageSubscriptionItem.target = self
        manageSubscriptionItem.image = AppIconProvider.menuImage(.appStore, accessibilityDescription: L10n.manageSubscription)
        appMenu.addItem(manageSubscriptionItem)
#endif
        let supportDeveloperItem = NSMenuItem(title: L10n.supportDeveloper, action: #selector(showSupportDeveloperWindow(_:)), keyEquivalent: "")
        supportDeveloperItem.target = self
        supportDeveloperItem.image = AppIconProvider.menuImage(.support, accessibilityDescription: L10n.supportDeveloper)
        appMenu.addItem(supportDeveloperItem)
        appMenu.addItem(.separator())
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

        let proItem = NSMenuItem()
        let proMenu = NSMenu(title: L10n.pro)
        let proUpgradeItem = makeMenuItem(title: L10n.upgradeToPro, action: #selector(showUpgradeProWindow(_:)), keyEquivalent: "", target: self)
        proUpgradeItem.image = AppIconProvider.menuImage(.pro, accessibilityDescription: L10n.upgradeToPro)
        proUpgradeMenuItem = proUpgradeItem
        proMenu.addItem(proUpgradeItem)
#if DEBUG
        let restorePurchasesItem = makeMenuItem(title: L10n.restorePurchases, action: #selector(restorePurchases(_:)), keyEquivalent: "", target: self)
        restorePurchasesItem.image = AppIconProvider.menuImage(.appStore, accessibilityDescription: L10n.restorePurchases)
        proMenu.addItem(restorePurchasesItem)
        let proManageSubscriptionItem = makeMenuItem(title: L10n.manageSubscription, action: #selector(manageSubscription(_:)), keyEquivalent: "", target: self)
        proManageSubscriptionItem.image = AppIconProvider.menuImage(.appStore, accessibilityDescription: L10n.manageSubscription)
        proMenu.addItem(proManageSubscriptionItem)
#endif
        proMenu.addItem(.separator())
        let stashShelfItem = makeMenuItem(title: L10n.proStashShelf, action: #selector(showProStashShelfWindow(_:)), keyEquivalent: "", target: self)
        stashShelfItem.image = AppIconProvider.menuImage(.folder, accessibilityDescription: L10n.proStashShelf)
        proMenu.addItem(stashShelfItem)
        proItem.submenu = proMenu
        mainMenu.addItem(proItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: L10n.view)
        addViewModeItem(title: L10n.viewModeList, key: "0", mode: .list, to: viewMenu)
        addViewModeItem(title: L10n.viewModeGrid, key: "9", mode: .grid, to: viewMenu)
        viewMenu.addItem(.separator())
        addLayoutItem(title: L10n.singlePane, key: "1", layout: .single, to: viewMenu)
        addLayoutItem(title: L10n.twoPanesVertical, key: "2", layout: .twoVertical, to: viewMenu)
        addLayoutItem(title: L10n.twoPanesHorizontal, key: "3", layout: .twoHorizontal, to: viewMenu)
        addLayoutItem(title: L10n.fourPanes, key: "8", layout: .fourGrid, to: viewMenu)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
        updateMonetizationMenuVisibility()
    }

    private func observeEntitlements() {
        entitlementCancellable = environment.entitlementService.$activeProductIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMonetizationMenuVisibility()
                }
            }
    }

    private func updateMonetizationMenuVisibility() {
#if DEBUG
        appUpgradeProMenuItem?.isHidden = false
        proUpgradeMenuItem?.isHidden = false
#else
        let shouldHideUpgrade = environment.entitlementService.isLifetimeUnlocked
        appUpgradeProMenuItem?.isHidden = shouldHideUpgrade
        proUpgradeMenuItem?.isHidden = shouldHideUpgrade
#endif
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

    func openDirectoryInNewWindow(_ url: URL) {
        let controller = showMainWindow()
        controller.setPaneLayout(.twoVertical)
        controller.openInActivePane(url)
    }

    @objc private func openOmniCaptureInAppStore(_ sender: Any?) {
        NSWorkspace.shared.open(omniCaptureAppStoreURL)
    }

    @objc private func showSupportDeveloperWindow(_ sender: Any?) {
        let controller = supportDeveloperWindowController ?? SupportDeveloperWindowController()
        supportDeveloperWindowController = controller
        controller.showWindow(self)
        guard let window = controller.window else { return }
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showUpgradeProWindow(_ sender: Any?) {
        let controller = upgradeProWindowController ?? UpgradeProWindowController(entitlementService: environment.entitlementService)
        upgradeProWindowController = controller
        controller.showWindow(self)
        guard let window = controller.window else { return }
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func restorePurchases(_ sender: Any?) {
        showUpgradeProWindow(sender)
        Task { [environment] in
            try? await environment.entitlementService.restorePurchases()
        }
    }

    @objc private func manageSubscription(_ sender: Any?) {
        environment.entitlementService.manageSubscriptions()
    }

    @objc private func showProWorkspacesWindow(_ sender: Any?) {
        guard ensureProAccess() else { return }
        let controller = proWorkspacesWindowController ?? ProWorkspacesWindowController(
            fetchWorkspaces: { [weak self] in
                guard let controller = self?.keyWindowController else { return [] }
                return (try? controller.savedWorkspaces()) ?? []
            },
            saveCurrentWorkspace: { [weak self] name in
                guard let controller = self?.keyWindowController else { return nil }
                return try? controller.saveWorkspace(named: name)
            },
            openWorkspace: { [weak self] workspace in self?.keyWindowController?.restoreWorkspace(workspace) },
            renameWorkspace: { [weak self] id, name in
                _ = try? self?.environment.workspaceStore.renameWorkspace(id: id, to: name)
            },
            deleteWorkspace: { [weak self] id in
                try? self?.environment.workspaceStore.deleteWorkspace(id: id)
            }
        )
        proWorkspacesWindowController = controller
        present(controller)
    }

    @objc private func showProStashShelfWindow(_ sender: Any?) {
        Task { [weak self] in
            guard let self else { return }
            await environment.entitlementService.refreshPurchasedProducts()
            showProStashShelfWindowAfterEntitlementRefresh(sender)
        }
    }

    private func showProStashShelfWindowAfterEntitlementRefresh(_ sender: Any?) {
        guard ensureProAccess() else { return }
        let controller = proStashShelfWindowController ?? ProStashShelfWindowController(
            stashShelfStore: try! StashShelfStore(),
            bookmarkStore: BookmarkStore(),
            fileOperationService: environment.fileOperationService,
            selectedURLsProvider: { [weak self] in self?.keyWindowController?.activePaneSelectedURLs() ?? [] },
            destinationURLProvider: { [weak self] in self?.keyWindowController?.activePaneURL }
        )
        proStashShelfWindowController = controller
        present(controller)
    }

    @objc private func showProBatchRenameWindow(_ sender: Any?) {
        guard ensureProAccess() else { return }
        let controller = proBatchRenameWindowController ?? ProBatchRenameWindowController(
            fileOperationService: environment.fileOperationService,
            selectedURLsProvider: { [weak self] in self?.keyWindowController?.activePaneSelectedURLs() ?? [] }
        )
        proBatchRenameWindowController = controller
        present(controller)
    }

    @objc private func showProFolderCompareWindow(_ sender: Any?) {
        guard ensureProAccess() else { return }
        let controller = proFolderCompareWindowController ?? ProFolderCompareWindowController(
            paneURLsProvider: { [weak self] in self?.keyWindowController?.paneURLs() ?? [] },
            fileProvider: environment.fileProvider
        )
        proFolderCompareWindowController = controller
        present(controller)
    }

    @objc private func showProPreferencesWindow(_ sender: Any?) {
        guard ensureProAccess() else { return }
        let controller = proPreferencesWindowController ?? ProPreferencesWindowController(
            toolbarPreferencesStore: environment.toolbarPreferencesStore,
            onToolbarPreferencesChanged: { [weak self] in self?.keyWindowController?.reloadToolbarConfiguration() }
        )
        proPreferencesWindowController = controller
        present(controller)
    }

    @objc private func refreshActivePane(_ sender: Any?) {
        keyWindowController?.refreshActivePane(sender)
    }

    @objc private func focusActivePathInput(_ sender: Any?) {
        keyWindowController?.focusActivePathInput(sender)
    }

    @objc private func createFolderInActivePane(_ sender: Any?) {
        activeWindowControllerForNewItemAction()?.createFolderInActivePane(sender)
    }

    @objc private func createTextFileInActivePane(_ sender: Any?) {
        activeWindowControllerForNewItemAction()?.createTextFileInActivePane(sender)
    }

    @objc private func renameSelectedItemInActivePane(_ sender: Any?) {
        keyWindowController?.renameSelectedItemInActivePane(sender)
    }

    @objc private func performNewItemActionInActivePane(_ sender: NSMenuItem) {
        activeWindowControllerForNewItemAction()?.performNewItemActionInActivePane(sender)
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
        guard !layout.isProOnly || ensureProAccess() else { return }
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

    private func activeWindowControllerForNewItemAction() -> MainWindowController? {
        let controller = keyWindowController ?? showMainWindow(reuseExisting: true)
        bringWindowToFront(controller)
        return controller
    }

    private func bringWindowToFront(_ controller: MainWindowController) {
        guard let window = controller.window else { return }
        if let screen = NSScreen.main, !screen.visibleFrame.intersects(window.frame) {
            window.center()
        }
        window.deminiaturize(self)
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func present(_ controller: NSWindowController) {
        controller.showWindow(self)
        guard let window = controller.window else { return }
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureProAccess() -> Bool {
        guard environment.entitlementService.isProUnlocked else {
            showUpgradeProWindow(nil)
            return false
        }
        return true
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
