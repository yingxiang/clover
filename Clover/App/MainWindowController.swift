import AppKit

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let rootViewController: RootSplitViewController

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

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.refresh, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == .refresh else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Refresh"
        item.paletteLabel = "Refresh"
        item.image = AppIconProvider.image(.refresh, accessibilityDescription: "Refresh")
        item.target = self
        item.action = #selector(refreshActivePane(_:))
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let refresh = NSToolbarItem.Identifier("CloverToolbar.Refresh")
}
