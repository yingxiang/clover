import AppKit
import Combine

@MainActor
protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarViewController(_ controller: SidebarViewController, didSelect url: URL)
}

final class SidebarViewController: NSViewController {
    weak var delegate: SidebarViewControllerDelegate?

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let upgradeButton = NSButton(title: L10n.upgradeToPro, target: nil, action: nil)
    private let entitlementService: EntitlementService
    private var upgradeProWindowController: UpgradeProWindowController?
    private var entitlementCancellable: AnyCancellable?
    private var scrollBottomToUpgradeConstraint: NSLayoutConstraint?
    private var scrollBottomToViewConstraint: NSLayoutConstraint?
    private var items: [SidebarItem] = []

    init(entitlementService: EntitlementService) {
        self.entitlementService = entitlementService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        items = Self.defaultItems()
        configureOutlineView()
        observeEntitlements()
    }

    private func configureOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.title = L10n.sidebarLocations
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.action = #selector(selectionChanged)

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        configureUpgradeButton()

        scrollBottomToUpgradeConstraint = scrollView.bottomAnchor.constraint(equalTo: upgradeButton.topAnchor, constant: -10)
        scrollBottomToViewConstraint = scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            upgradeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            upgradeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            upgradeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            upgradeButton.heightAnchor.constraint(equalToConstant: 34)
        ])
        scrollBottomToUpgradeConstraint?.isActive = true

        outlineView.reloadData()
        updateUpgradeButtonVisibility()
    }

    private func configureUpgradeButton() {
        upgradeButton.translatesAutoresizingMaskIntoConstraints = false
        upgradeButton.bezelStyle = .rounded
        upgradeButton.image = AppIconProvider.image(.pro, accessibilityDescription: L10n.upgradeToPro)
        upgradeButton.imagePosition = .imageLeading
        upgradeButton.contentTintColor = .controlAccentColor
        upgradeButton.font = .systemFont(ofSize: 13, weight: .semibold)
        upgradeButton.target = self
        upgradeButton.action = #selector(showUpgradeProWindow(_:))
        upgradeButton.toolTip = L10n.upgradeToPro
        upgradeButton.setAccessibilityLabel(L10n.upgradeToPro)
        view.addSubview(upgradeButton)
    }

    private func observeEntitlements() {
        entitlementCancellable = entitlementService.$activeProductIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateUpgradeButtonVisibility()
                }
            }
    }

    private func updateUpgradeButtonVisibility() {
#if DEBUG
        let shouldHideUpgrade = false
#else
        let shouldHideUpgrade = entitlementService.isLifetimeUnlocked
#endif
        upgradeButton.isHidden = shouldHideUpgrade
        scrollBottomToUpgradeConstraint?.isActive = !shouldHideUpgrade
        scrollBottomToViewConstraint?.isActive = shouldHideUpgrade
    }

    @objc private func selectionChanged() {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? SidebarItem else { return }
        delegate?.sidebarViewController(self, didSelect: item.url)
    }

    @objc private func showUpgradeProWindow(_ sender: Any?) {
        let controller = upgradeProWindowController ?? UpgradeProWindowController(entitlementService: entitlementService)
        upgradeProWindowController = controller
        controller.showWindow(self)
        guard let window = controller.window else { return }
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func defaultItems() -> [SidebarItem] {
        let home = UserDirectories.homeURL
        let userName = NSUserName()
        return [
            SidebarItem(title: userName.isEmpty ? L10n.sidebarHome : userName, url: home, systemIconName: AppSymbol.home.rawValue),
            SidebarItem(title: L10n.sidebarDesktop, url: home.appendingPathComponent("Desktop"), systemIconName: AppSymbol.desktop.rawValue),
            SidebarItem(title: L10n.sidebarDocuments, url: home.appendingPathComponent("Documents"), systemIconName: AppSymbol.documents.rawValue),
            SidebarItem(title: L10n.sidebarDownloads, url: home.appendingPathComponent("Downloads"), systemIconName: AppSymbol.downloads.rawValue),
            SidebarItem(title: L10n.sidebarApplications, url: URL(fileURLWithPath: "/Applications"), systemIconName: AppSymbol.applications.rawValue),
            SidebarItem(title: L10n.sidebarMovies, url: home.appendingPathComponent("Movies"), systemIconName: "movieclapper"),
            SidebarItem(title: L10n.sidebarMusic, url: home.appendingPathComponent("Music"), systemIconName: "music.note"),
            SidebarItem(title: L10n.sidebarPictures, url: home.appendingPathComponent("Pictures"), systemIconName: "photo")
        ]
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? items.count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let sidebarItem = item as? SidebarItem else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.imageView = imageView
            cell.textField = textField
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = sidebarItem.title
        if let systemIconName = sidebarItem.systemIconName {
            cell.imageView?.image = NSImage(systemSymbolName: systemIconName, accessibilityDescription: sidebarItem.title)
        }
        return cell
    }
}
