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
        controller.window?.makeKeyAndOrderFront(self)
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
        fileMenu.addItem(NSMenuItem(title: "Refresh", action: #selector(MainWindowController.refreshActivePane(_:)), keyEquivalent: "r"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        NSApp.mainMenu = mainMenu
    }
}
