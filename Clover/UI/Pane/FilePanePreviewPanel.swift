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

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor previewItem: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>) -> Any! {
        let transition = previewTransitionImage(for: previewItem)
        contentRect.pointee = transition.contentRect
        return transition.image
    }
}

extension FilePaneViewController {
    typealias PreviewTransition = (image: NSImage?, contentRect: NSRect)

    func previewItemURLsForCurrentMode() -> [URL] {
        switch viewModel.viewMode {
        case .list:
            return viewModel.listRows.map(\.item.url)
        case .grid:
            return viewModel.items.map(\.url)
        }
    }

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
        if let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? FileListNameCellView {
            return screenFrame(for: cell, rect: cell.previewSourceRect)
        }

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

    private func previewTransitionImage(for previewItem: QLPreviewItem) -> PreviewTransition {
        guard let url = previewItem.previewItemURL,
              let index = previewItems.firstIndex(of: url) else {
            return (nil, .zero)
        }

        switch viewModel.viewMode {
        case .list:
            return listPreviewTransition(at: index)
        case .grid:
            return gridPreviewTransition(at: index)
        }
    }

    private func listPreviewTransition(at index: Int) -> PreviewTransition {
        guard tableView.window != nil,
              index >= 0,
              index < tableView.numberOfRows else {
            return (nil, .zero)
        }

        tableView.scrollRowToVisible(index)
        tableView.layoutSubtreeIfNeeded()

        if let cell = tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? FileListNameCellView,
           let image = cell.previewTransitionImage {
            return (image, NSRect(origin: .zero, size: image.size))
        }

        guard let item = viewModel.item(at: index) else { return (nil, .zero) }
        let image = FileIconProvider.icon(for: item)
        return (image, NSRect(origin: .zero, size: image.size))
    }

    private func gridPreviewTransition(at index: Int) -> PreviewTransition {
        guard collectionView.window != nil,
              index >= 0,
              index < collectionView.numberOfItems(inSection: 0) else {
            return (nil, .zero)
        }

        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        collectionView.layoutSubtreeIfNeeded()

        if let item = collectionView.item(at: indexPath) as? FileGridItem,
           let image = item.imageView?.image {
            return (image, NSRect(origin: .zero, size: image.size))
        }

        guard let fileItem = viewModel.item(at: index) else { return (nil, .zero) }
        let image = FileIconProvider.icon(for: fileItem, size: 56)
        return (image, NSRect(origin: .zero, size: image.size))
    }
}
