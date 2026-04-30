import AppKit

extension FilePaneViewController: @preconcurrency NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = viewModel.item(at: row), let tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell-\(tableColumn.identifier.rawValue)")
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
            if tableColumn.identifier.rawValue == "name" {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyUpOrDown
                cell.addSubview(imageView)
                cell.imageView = imageView
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
        }

        cell.textField?.identifier = tableColumn.identifier.rawValue == "name" ? NSUserInterfaceItemIdentifier("FileNameEditor") : nil
        cell.textField?.tag = row
        cell.textField?.isEditable = tableColumn.identifier.rawValue == "name"
        cell.textField?.isSelectable = tableColumn.identifier.rawValue == "name"
        if tableColumn.identifier.rawValue == "name" {
            cell.imageView?.image = FileIconProvider.icon(for: item)
            cell.imageView?.toolTip = item.url.absoluteString
            Task { [weak imageView = cell.imageView] in
                guard let thumbnail = await FileThumbnailProvider.thumbnail(for: item, size: 18) else { return }
                await MainActor.run {
                    guard imageView?.toolTip == item.url.absoluteString else { return }
                    imageView?.image = thumbnail
                }
            }
        } else {
            cell.imageView?.image = nil
            cell.imageView?.toolTip = nil
        }
        cell.textField?.stringValue = value(for: item, columnIdentifier: tableColumn.identifier.rawValue)
        return cell
    }

    private func value(for item: FileItem, columnIdentifier: String) -> String {
        switch columnIdentifier {
        case "name":
            return item.name
        case "size":
            return detailValue(for: item, row: cellRow(for: item))
        case "modified":
            guard let date = item.modificationDate else { return "--" }
            return dateFormatter.string(from: date)
        default:
            return ""
        }
    }

    private func cellRow(for item: FileItem) -> Int {
        viewModel.items.firstIndex(where: { $0.url == item.url }) ?? 0
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        activationHandler?(self)
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

extension FilePaneViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField,
              textField.identifier?.rawValue == "FileNameEditor" else { return }
        renameItem(at: textField.tag, to: textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
