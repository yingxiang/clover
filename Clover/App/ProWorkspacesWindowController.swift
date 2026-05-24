import AppKit

@MainActor
final class ProWorkspacesWindowController: NSWindowController {
    private let fetchWorkspaces: () throws -> [Workspace]
    private let saveCurrentWorkspace: (_ name: String) throws -> Workspace?
    private let openWorkspace: (_ workspace: Workspace) -> Void
    private let renameWorkspace: (_ id: UUID, _ name: String) throws -> Void
    private let deleteWorkspace: (_ id: UUID) throws -> Void

    private let tableView = NSTableView()
    private let workspaces: NSMutableArray = []
    private var actionButtons: [NSButton] = []

    init(
        fetchWorkspaces: @escaping () throws -> [Workspace],
        saveCurrentWorkspace: @escaping (_ name: String) throws -> Workspace?,
        openWorkspace: @escaping (_ workspace: Workspace) -> Void,
        renameWorkspace: @escaping (_ id: UUID, _ name: String) throws -> Void,
        deleteWorkspace: @escaping (_ id: UUID) throws -> Void
    ) {
        self.fetchWorkspaces = fetchWorkspaces
        self.saveCurrentWorkspace = saveCurrentWorkspace
        self.openWorkspace = openWorkspace
        self.renameWorkspace = renameWorkspace
        self.deleteWorkspace = deleteWorkspace

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: L10n.proNamedWorkspaces)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: L10n.proNamedWorkspacesSubtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 0

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = L10n.name
        nameColumn.width = 220
        let layoutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layout"))
        layoutColumn.title = L10n.layout
        layoutColumn.width = 120
        let updatedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("updated"))
        updatedColumn.title = L10n.modified
        updatedColumn.width = 160
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(layoutColumn)
        tableView.addTableColumn(updatedColumn)
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true

        let saveButton = NSButton(title: L10n.saveCurrentWorkspace, target: nil, action: nil)
        let openButton = NSButton(title: L10n.open, target: nil, action: nil)
        let renameButton = NSButton(title: L10n.rename, target: nil, action: nil)
        let deleteButton = NSButton(title: L10n.deleteImmediately, target: nil, action: nil)
        let refreshButton = NSButton(title: L10n.refresh, target: nil, action: nil)
        actionButtons = [saveButton, openButton, renameButton, deleteButton, refreshButton]

        let buttonRow = NSStackView(views: [saveButton, openButton, renameButton, deleteButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        let stack = NSStackView(views: [titleLabel, subtitleLabel, scrollView, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.proNamedWorkspaces
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(openSelectedWorkspace(_:))
        tableView.target = self
        saveButton.target = self
        saveButton.action = #selector(saveCurrentWorkspaceAction(_:))
        openButton.target = self
        openButton.action = #selector(openSelectedWorkspace(_:))
        renameButton.target = self
        renameButton.action = #selector(renameSelectedWorkspace(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedWorkspace(_:))
        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))
        refresh(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func refresh(_ sender: Any?) {
        workspaces.removeAllObjects()
        if let items = try? fetchWorkspaces() {
            workspaces.addObjects(from: items)
        }
        tableView.reloadData()
    }

    @objc private func saveCurrentWorkspaceAction(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L10n.saveCurrentWorkspace
        alert.informativeText = L10n.proNamedWorkspacesSavePrompt
        alert.addButton(withTitle: L10n.save)
        alert.addButton(withTitle: L10n.cancel)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = L10n.proWorkspaceNamePlaceholder
        alert.accessoryView = input
        if alert.runModal() != .alertFirstButtonReturn { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = try? saveCurrentWorkspace(name)
        refresh(nil)
    }

    @objc private func openSelectedWorkspace(_ sender: Any?) {
        guard let workspace = selectedWorkspace() else { return }
        openWorkspace(workspace)
    }

    @objc private func renameSelectedWorkspace(_ sender: Any?) {
        guard let workspace = selectedWorkspace() else { return }
        let alert = NSAlert()
        alert.messageText = L10n.rename
        alert.informativeText = workspace.name
        alert.addButton(withTitle: L10n.ok)
        alert.addButton(withTitle: L10n.cancel)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = workspace.name
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        try? renameWorkspace(workspace.id, name)
        refresh(nil)
    }

    @objc private func deleteSelectedWorkspace(_ sender: Any?) {
        guard let workspace = selectedWorkspace() else { return }
        let alert = NSAlert()
        alert.messageText = L10n.deleteImmediatelyPrompt
        alert.informativeText = workspace.name
        alert.addButton(withTitle: L10n.deleteImmediately)
        alert.addButton(withTitle: L10n.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? deleteWorkspace(workspace.id)
        refresh(nil)
    }

    private func selectedWorkspace() -> Workspace? {
        guard let row = tableView.selectedRowIndexes.first,
              let workspace = workspaces[row] as? Workspace else { return nil }
        return workspace
    }
}

extension ProWorkspacesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        workspaces.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let workspace = workspaces[row] as? Workspace,
              let tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("Workspace-\(tableColumn.identifier.rawValue)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        switch tableColumn.identifier.rawValue {
        case "name":
            cell.textField?.stringValue = workspace.name
        case "layout":
            cell.textField?.stringValue = workspace.layout.rawValue
        case "updated":
            cell.textField?.stringValue = Self.dateFormatter.string(from: workspace.updatedAt)
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
