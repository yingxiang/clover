import AppKit

final class FilePaneViewController: NSViewController {
    let viewModel: FilePaneViewModel
    var activationHandler: ((FilePaneViewController) -> Void)?
    var statusHandler: ((String) -> Void)?

    private let pathBarView = PathBarView()
    private let tableView = FileTableView()
    private let scrollView = NSScrollView()
    private let loadingIndicator = NSProgressIndicator()
    private let contextMenu = NSMenu(title: "File Actions")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(viewModel: FilePaneViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        self.viewModel.onChange = { [weak self] in self?.reload() }
        self.viewModel.onStatusChange = { [weak self] text in
            self?.statusChanged(text)
            self?.statusHandler?(text)
        }
        self.viewModel.onError = { [weak self] error in self?.showError(error) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePathBar()
        configureTableView()
        configureLoadingIndicator()
        viewModel.load()
    }

    override func mouseDown(with event: NSEvent) {
        activationHandler?(self)
        super.mouseDown(with: event)
    }

    func setActive(_ isActive: Bool) {
        view.layer?.borderWidth = isActive ? 2 : 1
        view.layer?.borderColor = (isActive ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    func refresh() {
        viewModel.refresh()
    }

    func open(_ url: URL) {
        viewModel.load(url: url)
    }

    @objc func createFolder(_ sender: Any?) {
        activationHandler?(self)
        guard let name = promptForText(title: "New Folder", message: "Enter a folder name:", defaultValue: "Untitled Folder") else { return }
        runOperation {
            try await self.viewModel.createFolder(named: name)
        }
    }

    @objc func renameSelectedItem(_ sender: Any?) {
        activationHandler?(self)
        guard let item = selectedItems().first else { return }
        guard let name = promptForText(title: "Rename", message: "Enter a new name:", defaultValue: item.name), !name.isEmpty, name != item.name else { return }
        runOperation {
            try await self.viewModel.renameItem(item, to: name)
        }
    }

    @objc func copySelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, let destinationURL = chooseDestination(title: "Copy To") else { return }
        runOperation {
            try await self.viewModel.copyItems(items, to: destinationURL) { [weak self] conflict in
                await self?.resolveConflict(conflict) ?? .cancel
            }
        }
    }

    @objc func moveSelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, let destinationURL = chooseDestination(title: "Move To") else { return }
        runOperation {
            try await self.viewModel.moveItems(items, to: destinationURL) { [weak self] conflict in
                await self?.resolveConflict(conflict) ?? .cancel
            }
        }
    }

    @objc func trashSelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, confirmTrash(count: items.count) else { return }
        runOperation {
            try await self.viewModel.trashItems(items)
        }
    }

    @objc func focusPathInput(_ sender: Any?) {
        activationHandler?(self)
        pathBarView.beginEditing()
    }

    private func configurePathBar() {
        pathBarView.translatesAutoresizingMaskIntoConstraints = false
        pathBarView.navigationHandler = { [weak self] url in
            self?.viewModel.load(url: url)
        }
        pathBarView.pathSubmitHandler = { [weak self] path in
            self?.openSubmittedPath(path)
        }
        view.addSubview(pathBarView)
    }

    private func configureTableView() {
        let columns: [(String, String, CGFloat)] = [
            ("name", "Name", 280),
            ("size", "Size", 90),
            ("type", "Type", 160),
            ("modified", "Modified", 180)
        ]

        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .medium
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedItem)
        tableView.rightClickHandler = { [weak self] row in
            self?.prepareContextSelection(for: row)
        }
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            pathBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            pathBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            pathBarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            pathBarView.heightAnchor.constraint(equalToConstant: 26),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: pathBarView.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureLoadingIndicator() {
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.isDisplayedWhenStopped = false
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.trailingAnchor.constraint(equalTo: pathBarView.trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: pathBarView.centerYAnchor)
        ])
    }

    private func reload() {
        loadingIndicator.stopAnimation(nil)
        pathBarView.update(url: viewModel.currentURL)
        tableView.reloadData()
    }

    private func statusChanged(_ text: String) {
        if text.hasPrefix("Loading") {
            loadingIndicator.startAnimation(nil)
        }
    }

    private func showError(_ error: Error) {
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func selectedItems() -> [FileItem] {
        tableView.selectedRowIndexes.compactMap { viewModel.item(at: $0) }
    }

    private func prepareContextSelection(for row: Int) {
        activationHandler?(self)
        guard row >= 0 else {
            tableView.deselectAll(nil)
            return
        }
        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    private func runOperation(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch CloverError.operationCancelled {
                await MainActor.run {
                    statusChanged("Operation cancelled")
                    statusHandler?("Operation cancelled")
                }
            } catch {
                await MainActor.run { showError(error) }
            }
        }
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let input = NSTextField(string: defaultValue)
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func chooseDestination(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.directoryURL = viewModel.currentURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func confirmTrash(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move to Trash?"
        alert.informativeText = "Move \(count) selected item\(count == 1 ? "" : "s") to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func resolveConflict(_ conflict: FileConflict) async -> FileConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "An item named \"\(conflict.destinationURL.lastPathComponent)\" already exists."
        alert.informativeText = "Choose how Clover should handle the conflict."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .skip
        case .alertThirdButtonReturn:
            return .keepBoth
        default:
            return .cancel
        }
    }

    @objc private func openSelectedItem() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard let item = viewModel.item(at: row) else { return }

        if item.isDirectory {
            viewModel.load(url: item.url)
        } else {
            Task {
                do {
                    try await viewModel.openItem(item.url)
                } catch {
                    await MainActor.run { showError(error) }
                }
            }
        }
    }

    private func openSubmittedPath(_ path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        viewModel.load(url: url.standardizedFileURL)
    }
}

private final class FileTableView: NSTableView {
    var rightClickHandler: ((Int) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        rightClickHandler?(row(at: point))
        super.rightMouseDown(with: event)
    }
}

extension FilePaneViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let selectedCount = selectedItems().count
        if selectedCount == 0 {
            addMenuItem("New Folder", action: #selector(createFolder(_:)), to: menu)
            addMenuItem("Refresh", action: #selector(refreshFromContextMenu(_:)), to: menu)
            return
        }

        addMenuItem("Open", action: #selector(openSelectedItem), to: menu)
        menu.addItem(.separator())
        addMenuItem("Rename", action: #selector(renameSelectedItem(_:)), to: menu, enabled: selectedCount == 1)
        addMenuItem("Copy To...", action: #selector(copySelectedItems(_:)), to: menu)
        addMenuItem("Move To...", action: #selector(moveSelectedItems(_:)), to: menu)
        menu.addItem(.separator())
        addMenuItem("Move to Trash", action: #selector(trashSelectedItems(_:)), to: menu)
        menu.addItem(.separator())
        addMenuItem("New Folder", action: #selector(createFolder(_:)), to: menu)
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func refreshFromContextMenu(_ sender: Any?) {
        activationHandler?(self)
        refresh()
    }
}

extension FilePaneViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = viewModel.item(at: row), let tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell-\(tableColumn.identifier.rawValue)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = value(for: item, columnIdentifier: tableColumn.identifier.rawValue)
        return cell
    }

    private func value(for item: FileItem, columnIdentifier: String) -> String {
        switch columnIdentifier {
        case "name":
            return item.isDirectory ? "▸ \(item.name)" : item.name
        case "size":
            guard !item.isDirectory, let size = item.size else { return "--" }
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        case "type":
            return item.typeIdentifier ?? (item.isDirectory ? "Folder" : "File")
        case "modified":
            guard let date = item.modificationDate else { return "--" }
            return dateFormatter.string(from: date)
        default:
            return ""
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        activationHandler?(self)
    }
}
