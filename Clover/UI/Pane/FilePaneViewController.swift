import AppKit

final class FilePaneViewController: NSViewController {
    let viewModel: FilePaneViewModel
    var activationHandler: ((FilePaneViewController) -> Void)?

    private let pathLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let loadingIndicator = NSProgressIndicator()
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
        self.viewModel.onStatusChange = { [weak self] text in self?.statusChanged(text) }
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
        configurePathLabel()
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

    private func configurePathLabel() {
        pathLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pathLabel)
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

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            pathLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            pathLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            pathLabel.heightAnchor.constraint(equalToConstant: 22),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 6),
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
            loadingIndicator.trailingAnchor.constraint(equalTo: pathLabel.trailingAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor)
        ])
    }

    private func reload() {
        loadingIndicator.stopAnimation(nil)
        pathLabel.stringValue = viewModel.currentURL.path
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
