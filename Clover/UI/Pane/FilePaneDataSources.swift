import AppKit

extension FilePaneViewController: @preconcurrency NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.listRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = viewModel.item(at: row), let tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell-\(tableColumn.identifier.rawValue)")
        if tableColumn.identifier.rawValue == "name" {
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileListNameCellView ?? FileListNameCellView()
            cell.identifier = identifier
            cell.textField?.identifier = NSUserInterfaceItemIdentifier("FileNameEditor")
            cell.textField?.tag = row
            cell.textField?.delegate = self
            cell.textField?.stringValue = item.name
            cell.imageView?.image = FileIconProvider.icon(for: item)
            cell.imageView?.toolTip = item.url.absoluteString
            cell.disclosureButton.target = self
            cell.disclosureButton.action = #selector(toggleListDirectoryExpansion(_:))
            cell.disclosureButton.tag = row
            cell.configureDisclosure(
                depth: viewModel.listDepth(at: row),
                canExpand: viewModel.listRowCanExpand(at: row),
                isExpanded: viewModel.listRowIsExpanded(at: row)
            )
            Task { [weak imageView = cell.imageView] in
                guard let thumbnail = await FileThumbnailProvider.thumbnail(for: item, size: 18) else { return }
                await MainActor.run {
                    guard imageView?.toolTip == item.url.absoluteString else { return }
                    imageView?.image = thumbnail
                }
            }
            return cell
        }

        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let textField = NSTextField(string: "")
            textField.isBordered = false
            textField.isEditable = false
            textField.isSelectable = false
            textField.drawsBackground = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.delegate = self
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.identifier = nil
        cell.textField?.tag = row
        cell.textField?.isEditable = false
        cell.textField?.isSelectable = false
        cell.imageView?.image = nil
        cell.imageView?.toolTip = nil
        cell.textField?.stringValue = value(for: item, columnIdentifier: tableColumn.identifier.rawValue, row: row)
        return cell
    }

    private func value(for item: FileItem, columnIdentifier: String, row: Int) -> String {
        switch columnIdentifier {
        case "name":
            return item.name
        case "size":
            return detailValue(for: item, row: row)
        case "type":
            return FileItemPresentation.typeName(for: item)
        case "modified":
            guard let date = item.modificationDate else { return "--" }
            return dateFormatter.string(from: date)
        default:
            return ""
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        activationHandler?(self)
        updateCommandAvailability()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isUpdatingSortIndicators else { return }
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key else { return }
        setSortOption(for: key, ascending: descriptor.ascending)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        viewModel.item(at: row)?.url as NSURL?
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        writeDraggedItems(at: Array(rowIndexes), to: pasteboard)
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        info.draggingPasteboard.canReadFileURLs ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        performMoveDrop(info, itemIndex: row >= 0 ? row : nil)
    }

    @objc private func toggleListDirectoryExpansion(_ sender: NSButton) {
        activationHandler?(self)
        view.window?.makeFirstResponder(tableView)
        viewModel.toggleListExpansion(at: sender.tag)
    }
}

extension FilePaneViewController: NSCollectionViewDataSource, @preconcurrency NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FileGridItem.identifier, for: indexPath)
        if let gridItem = item as? FileGridItem, let fileItem = viewModel.item(at: indexPath.item) {
            gridItem.configure(with: fileItem)
            gridItem.renameHandler = { [weak self, weak collectionView] gridItem, newName in
                guard let collectionView,
                      let indexPath = collectionView.indexPath(for: gridItem) else { return }
                self?.renameItem(at: indexPath.item, to: newName)
            }
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        activationHandler?(self)
        updateCommandAvailability()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        updateCommandAvailability()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        viewModel.item(at: indexPath.item)?.url as NSURL?
    }

    func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
        writeDraggedItems(at: indexPaths.map(\.item), to: pasteboard)
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        proposedDropOperation.pointee = .on
        return draggingInfo.draggingPasteboard.canReadFileURLs ? .move : []
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        performMoveDrop(draggingInfo, itemIndex: indexPath.item)
    }
}

extension FilePaneViewController {
    func setSortOption(for key: String, ascending: Bool) {
        let option: SortOption?
        switch (key, ascending) {
        case ("name", true):
            option = .nameAscending
        case ("name", false):
            option = .nameDescending
        case ("size", true):
            option = .sizeAscending
        case ("size", false):
            option = .sizeDescending
        case ("modified", true):
            option = .dateAscending
        case ("modified", false):
            option = .dateDescending
        default:
            option = nil
        }
        guard let option else { return }
        viewModel.setSortOption(option)
    }

    func showTypeFilterMenu(for tableColumn: NSTableColumn) {
        guard let headerView = tableView.headerView else { return }
        let menu = NSMenu(title: L10n.type)
        let allItem = NSMenuItem(title: L10n.all, action: #selector(selectTypeFilter(_:)), keyEquivalent: "")
        allItem.target = self
        allItem.state = viewModel.typeFilter == nil ? .on : .off
        menu.addItem(allItem)

        for type in viewModel.availableTypeFilters {
            let item = NSMenuItem(title: type, action: #selector(selectTypeFilter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = type
            item.state = viewModel.typeFilter == type ? .on : .off
            menu.addItem(item)
        }

        let columnIndex = tableView.column(withIdentifier: tableColumn.identifier)
        let headerRect = headerView.headerRect(ofColumn: columnIndex)
        let point = NSPoint(x: headerRect.minX, y: headerRect.maxY)
        menu.popUp(positioning: menu.items.first, at: point, in: headerView)
        view.window?.makeFirstResponder(tableView)
        headerView.window?.invalidateCursorRects(for: headerView)
        NSCursor.arrow.set()
    }

    @objc private func selectTypeFilter(_ sender: NSMenuItem) {
        viewModel.setTypeFilter(sender.representedObject as? String)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.tableView)
            NSCursor.arrow.set()
        }
    }
}

extension FilePaneViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField,
              textField.identifier?.rawValue == "FileNameEditor" else { return }
        renameItem(at: textField.tag, to: textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
