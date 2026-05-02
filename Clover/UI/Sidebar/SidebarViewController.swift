import AppKit

@MainActor
protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarViewController(_ controller: SidebarViewController, didSelect url: URL)
}

final class SidebarViewController: NSViewController {
    weak var delegate: SidebarViewControllerDelegate?

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var items: [SidebarItem] = []

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        items = Self.defaultItems()
        configureOutlineView()
    }

    private func configureOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.title = "Locations"
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

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        outlineView.reloadData()
    }

    @objc private func selectionChanged() {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? SidebarItem else { return }
        delegate?.sidebarViewController(self, didSelect: item.url)
    }

    private static func defaultItems() -> [SidebarItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userName = NSUserName()
        return [
            SidebarItem(title: userName.isEmpty ? L10n.sidebarHome : userName, url: home, systemIconName: AppSymbol.home.rawValue),
            SidebarItem(title: L10n.sidebarDesktop, url: home.appendingPathComponent("Desktop"), systemIconName: AppSymbol.desktop.rawValue),
            SidebarItem(title: L10n.sidebarDocuments, url: home.appendingPathComponent("Documents"), systemIconName: AppSymbol.documents.rawValue),
            SidebarItem(title: L10n.sidebarDownloads, url: home.appendingPathComponent("Downloads"), systemIconName: AppSymbol.downloads.rawValue),
            SidebarItem(title: L10n.sidebarApplications, url: URL(fileURLWithPath: "/Applications"), systemIconName: AppSymbol.applications.rawValue),
            SidebarItem(title: L10n.sidebarMovies, url: home.appendingPathComponent("Movies"), systemIconName: "movieclapper"),
            SidebarItem(title: L10n.sidebarMusic, url: home.appendingPathComponent("Music"), systemIconName: "music.note"),
            SidebarItem(title: L10n.sidebarPictures, url: home.appendingPathComponent("Pictures"), systemIconName: "photo"),
            SidebarItem(title: L10n.sidebarVolumes, url: URL(fileURLWithPath: "/Volumes"), systemIconName: "externaldrive")
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
