import AppKit

@MainActor
final class ProBatchRenameWindowController: NSWindowController {
    private let fileOperationService: FileOperationService
    private let selectedURLsProvider: () -> [URL]

    private let tableView = NSTableView()
    private let prefixField = NSTextField()
    private let suffixField = NSTextField()
    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let startField = NSTextField(string: "1")
    private let refreshPreviewButton = NSButton(title: String(localized: "refresh", defaultValue: "Refresh"), target: nil, action: nil)
    private let executeButton = NSButton(title: String(localized: "batch_rename_execute", defaultValue: "Execute Renames"), target: nil, action: nil)

    private var items: [URL] = []
    private var previewRows: [(original: String, renamed: String)] = []

    init(
        fileOperationService: FileOperationService,
        selectedURLsProvider: @escaping () -> [URL]
    ) {
        self.fileOperationService = fileOperationService
        self.selectedURLsProvider = selectedURLsProvider

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: String(localized: "pro_batch_rename", defaultValue: "Batch Rename"))
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: String(localized: "pro_batch_rename_subtitle", defaultValue: "Preview and apply bulk filename changes."))
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 0

        let form = NSGridView(views: [
            [Self.label(String(localized: "prefix", defaultValue: "Prefix")), prefixField],
            [Self.label(String(localized: "suffix", defaultValue: "Suffix")), suffixField],
            [Self.label(String(localized: "find", defaultValue: "Find")), findField],
            [Self.label(String(localized: "replace", defaultValue: "Replace")), replaceField],
            [Self.label(String(localized: "start", defaultValue: "Start")), startField]
        ])
        form.rowSpacing = 8
        form.columnSpacing = 12
        prefixField.placeholderString = String(localized: "prefix", defaultValue: "Prefix")
        suffixField.placeholderString = String(localized: "suffix", defaultValue: "Suffix")
        findField.placeholderString = String(localized: "find", defaultValue: "Find")
        replaceField.placeholderString = String(localized: "replace", defaultValue: "Replace")
        startField.placeholderString = "1"
        startField.alignment = .right

        let buttonRow = NSStackView(views: [refreshPreviewButton, executeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let originalColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("original"))
        originalColumn.title = String(localized: "name", defaultValue: "Name")
        originalColumn.width = 240
        let renamedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("renamed"))
        renamedColumn.title = String(localized: "rename", defaultValue: "Rename")
        renamedColumn.width = 260
        tableView.addTableColumn(originalColumn)
        tableView.addTableColumn(renamedColumn)
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true

        let stack = NSStackView(views: [titleLabel, subtitleLabel, form, buttonRow, scrollView])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "pro_batch_rename", defaultValue: "Batch Rename")
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        refreshPreviewButton.target = self
        refreshPreviewButton.action = #selector(refreshPreview(_:))
        executeButton.target = self
        executeButton.action = #selector(execute(_:))
        tableView.delegate = self
        tableView.dataSource = self
        refreshPreview(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func refreshPreview(_ sender: Any?) {
        items = selectedURLsProvider()
        previewRows = items.enumerated().map { index, url in
            (url.lastPathComponent, Self.previewName(for: url, index: index, prefix: prefixField.stringValue, suffix: suffixField.stringValue, find: findField.stringValue, replace: replaceField.stringValue, start: startIndex))
        }
        tableView.reloadData()
    }

    @objc private func execute(_ sender: Any?) {
        refreshPreview(nil)
        guard !items.isEmpty else { return }
        Task {
            for (index, url) in items.enumerated() {
                let newName = Self.previewName(for: url, index: index, prefix: prefixField.stringValue, suffix: suffixField.stringValue, find: findField.stringValue, replace: replaceField.stringValue, start: startIndex)
                guard newName != url.lastPathComponent else { continue }
                _ = try? await fileOperationService.renameItem(at: url, to: newName)
            }
        }
    }

    private var startIndex: Int {
        Int(startField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
    }

    private static func previewName(for url: URL, index: Int, prefix: String, suffix: String, find: String, replace: String, start: Int) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var transformed = base
        if !find.isEmpty {
            transformed = transformed.replacingOccurrences(of: find, with: replace)
        }
        let numbered = "\(prefix)\(start + index)-\(transformed)\(suffix)"
        let finalBase = numbered.isEmpty ? transformed : numbered
        if ext.isEmpty {
            return finalBase
        }
        return "\(finalBase).\(ext)"
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }
}

extension ProBatchRenameWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        previewRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < previewRows.count, let tableColumn else { return nil }
        let rowData = previewRows[row]
        let identifier = NSUserInterfaceItemIdentifier("BatchRename-\(tableColumn.identifier.rawValue)")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        switch tableColumn.identifier.rawValue {
        case "original":
            cell.textField?.stringValue = rowData.original
        case "renamed":
            cell.textField?.stringValue = rowData.renamed
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }
}
