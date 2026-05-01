import AppKit

extension FilePaneViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let selectedCount = selectedItems().count
        if selectedCount == 0 {
            addMenuItem(L10n.newFolder, action: #selector(createFolder(_:)), to: menu)
            addMenuItem(L10n.refresh, action: #selector(refreshFromContextMenu(_:)), to: menu)
            return
        }

        addMenuItem(L10n.open, action: #selector(openSelectedItem), to: menu)
        menu.addItem(.separator())
        addMenuItem(L10n.rename, action: #selector(renameSelectedItem(_:)), to: menu, enabled: selectedCount == 1)
        addMenuItem(L10n.copyTo, action: #selector(copySelectedItems(_:)), to: menu)
        addMenuItem(L10n.moveTo, action: #selector(moveSelectedItems(_:)), to: menu)
        menu.addItem(.separator())
        addMenuItem(L10n.moveToTrash, action: #selector(trashSelectedItems(_:)), to: menu)
        menu.addItem(.separator())
        addMenuItem(L10n.newFolder, action: #selector(createFolder(_:)), to: menu)
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

    func prepareContextSelection(for index: Int?) {
        activationHandler?(self)
        switch viewModel.viewMode {
        case .list:
            guard let row = index, row >= 0 else {
                tableView.deselectAll(nil)
                return
            }
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        case .grid:
            guard let item = index, item >= 0 else {
                collectionView.deselectAll(nil)
                return
            }
            let indexPath = IndexPath(item: item, section: 0)
            if !collectionView.selectionIndexPaths.contains(indexPath) {
                collectionView.deselectAll(nil)
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
            }
        }
    }

    func rememberSelection(urls: [URL]) {
        pendingSelectionURLs = urls.map(\.standardizedFileURL)
    }

    func restorePendingSelectionIfNeeded() {
        guard !pendingSelectionURLs.isEmpty else { return }
        let urls = Set(pendingSelectionURLs)
        pendingSelectionURLs.removeAll()

        switch viewModel.viewMode {
        case .list:
            let indexes = viewModel.listRows.enumerated().compactMap { index, row in
                urls.contains(row.item.url.standardizedFileURL) ? index : nil
            }
            guard !indexes.isEmpty else { return }
            tableView.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
            tableView.scrollRowToVisible(indexes[0])
        case .grid:
            let indexPaths = viewModel.items.enumerated().compactMap { index, item in
                urls.contains(item.url.standardizedFileURL) ? IndexPath(item: index, section: 0) : nil
            }
            guard !indexPaths.isEmpty else { return }
            let selection = Set(indexPaths)
            collectionView.selectionIndexPaths = selection
            collectionView.scrollToItems(at: selection, scrollPosition: .centeredVertically)
        }
    }
}
