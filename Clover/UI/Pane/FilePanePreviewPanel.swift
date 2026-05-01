import Quartz

extension FilePaneViewController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        return handlePreviewPanelKeyDown(event)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel else { return }
        stopControllingPreviewPanel(panel)
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor previewItem: QLPreviewItem!) -> NSRect {
        previewSourceFrameOnScreen(for: previewItem)
    }
}

extension FilePaneViewController {
    func previewSourceFrameOnScreen(for previewItem: QLPreviewItem) -> NSRect {
        guard let url = previewItem.previewItemURL,
              let index = previewItems.firstIndex(of: url) else {
            return .zero
        }

        switch viewModel.viewMode {
        case .list:
            return listPreviewSourceFrameOnScreen(at: index)
        case .grid:
            return gridPreviewSourceFrameOnScreen(at: index)
        }
    }

    private func listPreviewSourceFrameOnScreen(at index: Int) -> NSRect {
        guard tableView.window != nil,
              index >= 0,
              index < tableView.numberOfRows else {
            return .zero
        }

        tableView.scrollRowToVisible(index)
        tableView.layoutSubtreeIfNeeded()
        let cellFrame = tableView.frameOfCell(atColumn: 0, row: index)
        let sourceFrame = cellFrame.isEmpty ? tableView.rect(ofRow: index) : cellFrame
        return screenFrame(for: tableView, rect: sourceFrame.insetBy(dx: 2, dy: 2))
    }

    private func gridPreviewSourceFrameOnScreen(at index: Int) -> NSRect {
        guard collectionView.window != nil,
              index >= 0,
              index < collectionView.numberOfItems(inSection: 0) else {
            return .zero
        }

        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        collectionView.layoutSubtreeIfNeeded()

        if let item = collectionView.item(at: indexPath) as? FileGridItem {
            return item.view.window?.convertToScreen(item.previewSourceRect) ?? .zero
        }

        let itemFrame = collectionView.frameForItem(at: index)
        guard !itemFrame.isEmpty else { return .zero }
        let iconFrame = NSRect(
            x: itemFrame.midX - 30,
            y: itemFrame.maxY - 63,
            width: 60,
            height: 58
        )
        return screenFrame(for: collectionView, rect: iconFrame)
    }

    private func screenFrame(for view: NSView, rect: NSRect) -> NSRect {
        guard let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(rect, to: nil))
    }
}
