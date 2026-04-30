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
}
