import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
final class ProStashShelfWindowController: NSWindowController {
    private static let inactiveAlpha: CGFloat = 0.88
    private static let activeAlpha: CGFloat = 1.0

    private let stashShelfStore: StashShelfStore
    private let bookmarkStore: BookmarkStore
    private let surfaceView = StashShelfSurfaceView()
    private var items: [StashItem] = []
    private var listPopover: NSPopover?
    private var activeDragSecurityScopes: [(url: URL, didStartAccessing: Bool)] = []

    init(
        stashShelfStore: StashShelfStore,
        bookmarkStore: BookmarkStore,
        fileOperationService: FileOperationService,
        selectedURLsProvider: @escaping () -> [URL],
        destinationURLProvider: @escaping () -> URL?
    ) {
        self.stashShelfStore = stashShelfStore
        self.bookmarkStore = bookmarkStore
        _ = fileOperationService
        _ = selectedURLsProvider
        _ = destinationURLProvider

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 132),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = surfaceView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
//        window.alphaValue = Self.inactiveAlpha

        super.init(window: window)

        surfaceView.closeHandler = { [weak self] in self?.window?.close() }
        surfaceView.clearHandler = { [weak self] in self?.clearStash() }
        surfaceView.dropHandler = { [weak self] draggingInfo in
            self?.acceptStashDrop(draggingInfo) ?? false
        }
        
        surfaceView.dragPresenceChanged = { [weak self] isInside in
//            self?.window?.alphaValue = isInside ? Self.activeAlpha : Self.inactiveAlpha
            self?.surfaceView.setDropHighlight(isInside)
        }
        surfaceView.thumbnailClicked = { [weak self] anchor in
            self?.toggleListPopover(anchor: anchor)
        }
        surfaceView.dragItemsProvider = { [weak self] in
            self?.stashedPasteboardItems() ?? []
        }
        surfaceView.dragEndedHandler = { [weak self] operation, screenPoint in
            self?.finishStashDrag(operation: operation, screenPoint: screenPoint)
        }
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refresh() {
        let loadedItems = (try? stashShelfStore.loadItems()) ?? []
        let uniqueItems = deduplicatedItems(loadedItems)
        if uniqueItems.count != loadedItems.count {
            try? stashShelfStore.saveItems(uniqueItems)
        }
        items = uniqueItems
        surfaceView.configure(items: items)
        if let popover = listPopover, popover.isShown {
            if items.isEmpty {
                popover.performClose(nil)
                listPopover = nil
            } else if let controller = popover.contentViewController as? StashShelfListViewController {
                controller.configure(items: items)
                popover.contentSize = controller.preferredContentSize
            }
        }
    }

    private func acceptStashDrop(_ draggingInfo: NSDraggingInfo) -> Bool {
        guard let urls = draggingInfo.draggingPasteboard.stashFileURLs, !urls.isEmpty else {
            window?.alphaValue = Self.inactiveAlpha
            surfaceView.setDropHighlight(false)
            return false
        }
        let existingPaths = Set(items.map { canonicalPath(for: $0) })
        let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
            let path = Self.canonicalPath(for: url)
            guard !existingPaths.contains(path),
                  !result.contains(where: { Self.canonicalPath(for: $0) == path }) else { return }
            result.append(url)
        }
        if !uniqueURLs.isEmpty {
            _ = try? stashShelfStore.addItems(uniqueURLs, bookmarkStore: bookmarkStore)
        }
//        window?.alphaValue = Self.inactiveAlpha
        surfaceView.setDropHighlight(false)
        refresh()
        return true
    }

    private func toggleListPopover(anchor: NSView) {
        guard !items.isEmpty else { return }
        if let popover = listPopover, popover.isShown {
            if let controller = popover.contentViewController as? StashShelfListViewController {
                controller.animateCollapse { [weak self, weak popover] in
                    popover?.performClose(nil)
                    self?.listPopover = nil
                }
            } else {
                popover.performClose(nil)
                listPopover = nil
            }
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = StashShelfListViewController(items: items) { [weak self] item in
            self?.removeStashItem(item)
        }
        listPopover = popover
        let anchorRect = NSRect(x: anchor.bounds.midX - 1, y: anchor.bounds.minY, width: 2, height: 2)
        popover.show(relativeTo: anchorRect, of: anchor, preferredEdge: .minY)
    }

    private func removeStashItem(_ item: StashItem) {
        try? stashShelfStore.removeItem(id: item.id)
        refresh()
    }

    private func clearStash() {
        try? stashShelfStore.clear()
        refresh()
    }

    private func finishStashDrag(operation: NSDragOperation, screenPoint: NSPoint) {
        surfaceView.setStashedFilesDragging(false)
        stopDragSecurityScopes()
        guard !operation.isEmpty else { return }
        guard window?.frame.contains(screenPoint) != true else { return }
        clearStash()
    }

    private func stashedPasteboardItems() -> [any NSPasteboardWriting] {
        let urls = items.compactMap(\.url)
        startDragSecurityScopes(for: urls)
        return urls.map { url in
            CloverPasteboardFile(url: url, isDirectory: Self.isDirectory(url)).pasteboardItem()
        }
    }

    private func startDragSecurityScopes(for urls: [URL]) {
        stopDragSecurityScopes()
        var scopedPaths: Set<String> = []
        activeDragSecurityScopes = urls.compactMap { url in
            let securityScopeURL = url.standardizedFileURL
            let path = securityScopeURL.path
            guard scopedPaths.insert(path).inserted else { return nil }
            return (url: securityScopeURL, didStartAccessing: securityScopeURL.startAccessingSecurityScopedResource())
        }
    }

    private func stopDragSecurityScopes() {
        for scope in activeDragSecurityScopes where scope.didStartAccessing {
            scope.url.stopAccessingSecurityScopedResource()
        }
        activeDragSecurityScopes.removeAll()
    }

    private func deduplicatedItems(_ items: [StashItem]) -> [StashItem] {
        var seenPaths: Set<String> = []
        return items.filter { item in
            let path = canonicalPath(for: item)
            guard !seenPaths.contains(path) else { return false }
            seenPaths.insert(path)
            return true
        }
    }

    private func canonicalPath(for item: StashItem) -> String {
        Self.canonicalPath(for: URL(fileURLWithPath: item.path, isDirectory: false))
    }

    private static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
    }
}

private final class StashShelfSurfaceView: NSView {
    private enum Metrics {
        static let glassCornerRadius: CGFloat = 12
        static let glassBorderWidth: CGFloat = 1
        static let dropBorderWidth: CGFloat = 2
    }

    var closeHandler: (() -> Void)?
    var clearHandler: (() -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?
    var dragPresenceChanged: ((Bool) -> Void)?
    var thumbnailClicked: ((NSView) -> Void)?
    var dragItemsProvider: (() -> [any NSPasteboardWriting])?
    var dragStartedHandler: (() -> Void)?
    var dragEndedHandler: ((NSDragOperation, NSPoint) -> Void)?

    private let glassView = StashShelfSurfaceView.makeGlassBackgroundView()
    private let plusImageView = StashPassthroughImageView()
    private let thumbnailStackView = StashThumbnailStackView()
    private let dropCatcherView = StashShelfDropCatcherView()
    private let moveButton = StashShelfMoveButton(symbolName: "arrow.up.and.down.and.arrow.left.and.right", pointSize: 11)
    private let countBadgeView = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private var hasItems = false
    private var items: [StashItem] = []
    private var mouseDownEvent: NSEvent?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let hitView = super.hitTest(point)
        if hitView === moveButton || hitView === dropCatcherView || hasItems {
            return hitView
        }
        return self
    }

    func configure(items: [StashItem]) {
        self.items = items
        let isEmpty = items.isEmpty
        hasItems = !isEmpty
        glassView.isHidden = false
//        glassView.alphaValue = isEmpty ? 1 : 0.42
        plusImageView.isHidden = !isEmpty
        thumbnailStackView.isHidden = isEmpty
        moveButton.isHidden = isEmpty
        countBadgeView.isHidden = isEmpty
        countLabel.stringValue = "\(items.count)"
        setStashedFilesDragging(false)
        updateBorder(isDropTargeted: false)
        thumbnailStackView.configure(items: items)
    }

    func setStashedFilesDragging(_ isDragging: Bool) {
        thumbnailStackView.alphaValue = isDragging ? 0 : 1
        countBadgeView.alphaValue = isDragging ? 0 : 1
    }

    func setDropHighlight(_ isDropTargeted: Bool) {
        updateBorder(isDropTargeted: isDropTargeted)
//        glassView.alphaValue = isDropTargeted ? 0.72 : (hasItems ? 0.42 : 1)
    }

    private func setup() {
        registerForDraggedTypes([.fileURL, .URL])
        wantsLayer = true
        layer?.masksToBounds = false

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = Metrics.glassCornerRadius
        glassView.layer?.borderWidth = Metrics.glassBorderWidth
        glassView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.9).cgColor
        addSubview(glassView)

        plusImageView.translatesAutoresizingMaskIntoConstraints = false
        plusImageView.image = NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.proStashShelf)
        plusImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        plusImageView.contentTintColor = .labelColor.withAlphaComponent(0.7)
        plusImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(plusImageView)

        thumbnailStackView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailStackView.isHidden = true
        thumbnailStackView.clickHandler = { [weak self] anchor in
            self?.thumbnailClicked?(anchor)
        }
        thumbnailStackView.dropHandler = { [weak self] draggingInfo in
            self?.dropHandler?(draggingInfo) ?? false
        }
        thumbnailStackView.dragPresenceChanged = { [weak self] isInside in
            self?.dragPresenceChanged?(isInside)
        }
        thumbnailStackView.dragItemsProvider = { [weak self] in
            self?.dragItemsProvider?() ?? []
        }
        thumbnailStackView.dragStartedHandler = { [weak self] in
            self?.setStashedFilesDragging(true)
            self?.dragStartedHandler?()
        }
        thumbnailStackView.dragEndedHandler = { [weak self] operation, screenPoint in
            self?.dragEndedHandler?(operation, screenPoint)
        }
        thumbnailStackView.menuProvider = { [weak self] in
            self?.contextMenu()
        }
        addSubview(thumbnailStackView)

        dropCatcherView.translatesAutoresizingMaskIntoConstraints = false
        dropCatcherView.hasItemsProvider = { [weak self] in
            self?.hasItems ?? false
        }
        dropCatcherView.clickHandler = { [weak self] in
            guard let self else { return }
            thumbnailClicked?(thumbnailStackView)
        }
        dropCatcherView.dropHandler = { [weak self] draggingInfo in
            self?.dropHandler?(draggingInfo) ?? false
        }
        dropCatcherView.dragPresenceChanged = { [weak self] isInside in
            self?.dragPresenceChanged?(isInside)
        }
        dropCatcherView.dragItemsProvider = { [weak self] in
            self?.dragItemsProvider?() ?? []
        }
        dropCatcherView.dragStartedHandler = { [weak self] in
            self?.setStashedFilesDragging(true)
            self?.dragStartedHandler?()
        }
        dropCatcherView.dragEndedHandler = { [weak self] operation, screenPoint in
            self?.dragEndedHandler?(operation, screenPoint)
        }
        dropCatcherView.dragImageProvider = { [weak self] in
            self?.thumbnailStackView.snapshotImage() ?? NSImage()
        }
        dropCatcherView.menuProvider = { [weak self] in
            self?.contextMenu()
        }
        addSubview(dropCatcherView)

        moveButton.translatesAutoresizingMaskIntoConstraints = false
        moveButton.toolTip = "Move"
        addSubview(moveButton)

        countBadgeView.translatesAutoresizingMaskIntoConstraints = false
        countBadgeView.wantsLayer = true
        countBadgeView.layer?.backgroundColor = NSColor.systemRed.cgColor
        countBadgeView.layer?.cornerRadius = 9
        countBadgeView.isHidden = true
        addSubview(countBadgeView)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .white
        countLabel.alignment = .center
        countBadgeView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            glassView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            plusImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            plusImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            plusImageView.widthAnchor.constraint(equalToConstant: 44),
            plusImageView.heightAnchor.constraint(equalToConstant: 44),

            thumbnailStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailStackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            thumbnailStackView.widthAnchor.constraint(equalToConstant: 108),
            thumbnailStackView.heightAnchor.constraint(equalToConstant: 90),

            dropCatcherView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dropCatcherView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dropCatcherView.topAnchor.constraint(equalTo: topAnchor),
            dropCatcherView.bottomAnchor.constraint(equalTo: bottomAnchor),

            moveButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            moveButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            moveButton.widthAnchor.constraint(equalToConstant: 27),
            moveButton.heightAnchor.constraint(equalToConstant: 27),

            countBadgeView.centerXAnchor.constraint(equalTo: centerXAnchor),
            countBadgeView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            countBadgeView.heightAnchor.constraint(equalToConstant: 18),
            countBadgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),

            countLabel.leadingAnchor.constraint(equalTo: countBadgeView.leadingAnchor, constant: 7),
            countLabel.trailingAnchor.constraint(equalTo: countBadgeView.trailingAnchor, constant: -7),
            countLabel.centerYAnchor.constraint(equalTo: countBadgeView.centerYAnchor)
        ])
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let clearItem = NSMenuItem(title: L10n.clearStashShelf, action: #selector(clearClicked(_:)), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = hasItems
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: L10n.closeWindow, action: #selector(closeClicked(_:)), keyEquivalent: "")
        closeItem.target = self; menu.addItem(closeItem)
        return menu
    }

    @objc private func clearClicked(_ sender: Any?) {
        clearHandler?()
    }

    @objc private func closeClicked(_ sender: Any?) {
        closeHandler?()
    }

    override func mouseDown(with event: NSEvent) {
        guard !hasItems else {
            super.mouseDown(with: event)
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasItems else {
            super.mouseDragged(with: event)
            return
        }
        if NSApp.currentEvent === event {
            window?.performDrag(with: mouseDownEvent ?? event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        super.mouseUp(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadStashFileURLs else { return [] }
        dragPresenceChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadStashFileURLs ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragPresenceChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dragPresenceChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandler?(sender) ?? false
    }

    private func updateBorder(isDropTargeted: Bool) {
        glassView.layer?.borderWidth = isDropTargeted ? Metrics.dropBorderWidth : Metrics.glassBorderWidth
        glassView.layer?.borderColor = (isDropTargeted
            ? NSColor.controlAccentColor
            : NSColor.separatorColor.withAlphaComponent(0.9)
        ).cgColor
        glassView.layer?.backgroundColor = (isDropTargeted
            ? NSColor.controlAccentColor.withAlphaComponent(0.16)
            : NSColor.clear
        ).cgColor
        layer?.shadowColor = (isDropTargeted ? NSColor.controlAccentColor : NSColor.clear).cgColor
        layer?.shadowOpacity = isDropTargeted ? 0.25 : 0
        layer?.shadowRadius = isDropTargeted ? 8 : 0
        layer?.shadowOffset = .zero
    }

    private static func makeGlassBackgroundView() -> NSView {
        if #available(macOS 26.0, *) {
            let view = StashPassthroughGlassEffectView()
            view.style = .regular
            view.cornerRadius = Metrics.glassCornerRadius
            view.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.08)
            return view
        }
        let view = StashPassthroughVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

}

private final class StashPassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class StashPassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@available(macOS 26.0, *)
private final class StashPassthroughGlassEffectView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class StashShelfDropCatcherView: NSView {
    var hasItemsProvider: (() -> Bool)?
    var clickHandler: (() -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?
    var dragPresenceChanged: ((Bool) -> Void)?
    var dragItemsProvider: (() -> [any NSPasteboardWriting])?
    var dragImageProvider: (() -> NSImage)?
    var menuProvider: (() -> NSMenu?)?
    var dragStartedHandler: (() -> Void)?
    var dragEndedHandler: ((NSDragOperation, NSPoint) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didBeginFileDrag = false
    private var isReceivingExternalDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !bounds.contains(point) ? nil : self
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isReceivingExternalDrag else { return }
        mouseDownEvent = event
        didBeginFileDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isReceivingExternalDrag else { return }
        if hasItemsProvider?() == true {
            beginFileDrag(with: event)
        } else {
            window?.performDrag(with: mouseDownEvent ?? event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if hasItemsProvider?() == true, !didBeginFileDrag {
            clickHandler?()
        }
        mouseDownEvent = nil
        didBeginFileDrag = false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource as AnyObject? !== self,
              sender.draggingPasteboard.canReadStashFileURLs else { return [] }
        isReceivingExternalDrag = true
        dragPresenceChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadStashFileURLs ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingExternalDrag = false
        dragPresenceChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isReceivingExternalDrag = false
        dragPresenceChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceivingExternalDrag = false
        return dropHandler?(sender) ?? false
    }

    private func beginFileDrag(with event: NSEvent) {
        guard !didBeginFileDrag, let items = dragItemsProvider?(), !items.isEmpty else { return }
        didBeginFileDrag = true
        let snapshot = dragImageProvider?() ?? NSImage(size: bounds.size)
        let draggingFrame = centeredDraggingFrame(for: snapshot, in: bounds)
        let draggingItems = items.map { pasteboardWriter in
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
            draggingItem.setDraggingFrame(draggingFrame, contents: snapshot)
            return draggingItem
        }
        dragStartedHandler?()
        beginDraggingSession(with: draggingItems, event: mouseDownEvent ?? event, source: self)
    }
}

extension StashShelfDropCatcherView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragEndedHandler?(operation, screenPoint)
    }
}

private final class StashThumbnailStackView: NSView {
    var clickHandler: ((NSView) -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?
    var dragPresenceChanged: ((Bool) -> Void)?
    var dragItemsProvider: (() -> [any NSPasteboardWriting])?
    var menuProvider: (() -> NSMenu?)?
    var dragStartedHandler: (() -> Void)?
    var dragEndedHandler: ((NSDragOperation, NSPoint) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didBeginFileDrag = false
    private var isReceivingExternalDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !bounds.contains(point) ? nil : self
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    func configure(items: [StashItem]) {
        subviews.forEach { $0.removeFromSuperview() }
        guard !items.isEmpty else { return }

        let visibleItems = Array(items.suffix(4))
        let layout = Self.stackLayout(for: visibleItems.count)
        for (index, item) in visibleItems.enumerated() {
            let placement = layout[index]
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.image = StashPreviewImageProvider.icon(for: item)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 5
            imageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
            imageView.layer?.borderWidth = 0
            imageView.layer?.shadowColor = NSColor.black.cgColor
            imageView.layer?.shadowOpacity = 0.22
            imageView.layer?.shadowRadius = 8
            imageView.layer?.shadowOffset = NSSize(width: 0, height: -2)
            imageView.layer?.masksToBounds = false
            imageView.frameCenterRotation = placement.rotation
            addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: placement.x),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: placement.y),
                imageView.widthAnchor.constraint(equalToConstant: 72),
                imageView.heightAnchor.constraint(equalToConstant: 72)
            ])
            Task { [weak imageView] in
                guard let thumbnail = await StashPreviewImageProvider.thumbnail(for: item, size: 72) else { return }
                imageView?.image = thumbnail
            }
        }
    }

    private static func stackLayout(for count: Int) -> [(x: CGFloat, y: CGFloat, rotation: CGFloat)] {
        switch count {
        case 0, 1:
            return [(0, 0, 0)]
        case 2:
            return [(-7, 3, -4), (9, -4, 5)]
        case 3:
            return [(-14, 6, -7), (0, 0, -1), (14, -6, 6)]
        default:
            return [(-18, 8, -8), (-6, 2, -3), (8, -4, 3), (20, -8, 8)]
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isReceivingExternalDrag else { return }
        mouseDownEvent = event
        didBeginFileDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isReceivingExternalDrag else { return }
        guard !didBeginFileDrag, let items = dragItemsProvider?(), !items.isEmpty else { return }
        didBeginFileDrag = true
        let snapshot = snapshotImage()
        let draggingFrame = centeredDraggingFrame(for: snapshot, in: bounds)
        let draggingItems = items.map { pasteboardWriter in
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
            draggingItem.setDraggingFrame(draggingFrame, contents: snapshot)
            return draggingItem
        }
        dragStartedHandler?()
        beginDraggingSession(with: draggingItems, event: mouseDownEvent ?? event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginFileDrag {
            clickHandler?(self)
        }
        mouseDownEvent = nil
        didBeginFileDrag = false
    }

    func snapshotImage() -> NSImage {
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadStashFileURLs else { return [] }
        isReceivingExternalDrag = true
        dragPresenceChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadStashFileURLs ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingExternalDrag = false
        dragPresenceChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isReceivingExternalDrag = false
        dragPresenceChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceivingExternalDrag = false
        return dropHandler?(sender) ?? false
    }
}

extension StashThumbnailStackView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragEndedHandler?(operation, screenPoint)
    }
}

private class StashShelfIconButton: NSControl {
    private let symbolName: String
    private let pointSize: CGFloat
    private var isPressed = false

    init(symbolName: String, pointSize: CGFloat) {
        self.symbolName = symbolName
        self.pointSize = pointSize
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let circleRect = bounds.insetBy(dx: 1, dy: 1)
        NSColor.black.withAlphaComponent(isPressed ? 0.74 : 0.58).setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        let pointConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(pointConfiguration.applying(colorConfiguration)) else {
            return
        }

        let imageSize = symbol.size
        let imageRect = NSRect(x: bounds.midX - imageSize.width / 2, y: bounds.midY - imageSize.height / 2, width: imageSize.width, height: imageSize.height)
        symbol.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        sendAction(action, to: target)
    }
}

private final class StashShelfMoveButton: StashShelfIconButton {
    private var mouseDownEvent: NSEvent?

    override init(symbolName: String, pointSize: CGFloat) {
        super.init(symbolName: symbolName, pointSize: pointSize)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: mouseDownEvent ?? event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        mouseDownEvent = nil
    }
}

private final class StashShelfListViewController: NSViewController {
    private static let itemWidth: CGFloat = 78
    private static let itemHeight: CGFloat = 92
    private static let itemSpacing: CGFloat = 10
    private static let horizontalInset: CGFloat = 12
    private static let topInset: CGFloat = 18
    private static let bottomInset: CGFloat = 10

    private var items: [StashItem]
    private let removeHandler: (StashItem) -> Void
    private let stackView = NSStackView()
    private var itemViews: [NSView] = []
    private var collapseCompletion: (() -> Void)?

    init(items: [StashItem], removeHandler: @escaping (StashItem) -> Void) {
        self.items = items
        self.removeHandler = removeHandler
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.contentSize(for: items.count)
    }

    private static func contentSize(for itemCount: Int) -> NSSize {
        let contentWidth = CGFloat(itemCount) * Self.itemWidth
            + CGFloat(max(0, itemCount - 1)) * Self.itemSpacing
            + Self.horizontalInset * 2
        return NSSize(
            width: min(520, max(Self.itemWidth + Self.horizontalInset * 2, contentWidth)),
            height: Self.itemHeight + Self.topInset + Self.bottomInset
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = Self.itemSpacing
        stackView.edgeInsets = NSEdgeInsets(
            top: Self.topInset,
            left: Self.horizontalInset,
            bottom: Self.bottomInset,
            right: Self.horizontalInset
        )
        reloadItemViews()

        scrollView.documentView = stackView
        visualEffectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            stackView.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.widthAnchor)
        ])
        view = visualEffectView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        animateExpansion()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateStackInsets()
    }

    func configure(items: [StashItem]) {
        self.items = items
        preferredContentSize = Self.contentSize(for: items.count)
        reloadItemViews()
        updateStackInsets()
    }

    func animateCollapse(completion: @escaping () -> Void) {
        view.layoutSubtreeIfNeeded()
        collapseCompletion = completion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            itemViews.forEach { itemView in
                itemView.animator().alphaValue = 0
                itemView.animator().frame.origin.x = view.bounds.midX - itemView.bounds.width / 2
                itemView.animator().frame.origin.y = view.bounds.midY - itemView.bounds.height / 2
            }
        }
        perform(#selector(finishCollapseAnimation), with: nil, afterDelay: 0.16)
    }

    private func animateExpansion() {
        view.layoutSubtreeIfNeeded()
        let finalFrames = itemViews.map(\.frame)
        itemViews.forEach { itemView in
            itemView.alphaValue = 0
            itemView.frame.origin.x = view.bounds.midX - itemView.bounds.width / 2
            itemView.frame.origin.y = view.bounds.midY - itemView.bounds.height / 2
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            itemViews.enumerated().forEach { index, itemView in
                itemView.animator().alphaValue = 1
                itemView.animator().frame = finalFrames[index]
            }
        }
    }

    @objc private func finishCollapseAnimation() {
        collapseCompletion?()
        collapseCompletion = nil
    }

    private func reloadItemViews() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        itemViews.removeAll()
        items.forEach { item in
            let itemView = StashShelfListItemView(item: item) { [weak self] in
                self?.removeHandler(item)
            }
            itemViews.append(itemView)
            stackView.addArrangedSubview(itemView)
        }
    }

    private func updateStackInsets() {
        let contentWidth = CGFloat(items.count) * Self.itemWidth
            + CGFloat(max(0, items.count - 1)) * Self.itemSpacing
        let horizontalInset = max(Self.horizontalInset, (view.bounds.width - contentWidth) / 2)
        stackView.edgeInsets = NSEdgeInsets(
            top: Self.topInset,
            left: horizontalInset,
            bottom: Self.bottomInset,
            right: horizontalInset
        )
    }
}

private final class StashShelfListItemView: NSView {
    private let removeHandler: () -> Void

    init(item: StashItem, removeHandler: @escaping () -> Void) {
        self.removeHandler = removeHandler
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = StashPreviewImageProvider.icon(for: item)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 5
        imageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        imageView.layer?.masksToBounds = false

        let closeButton = StashShelfIconButton(symbolName: "xmark", pointSize: 8)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(removeClicked(_:))
        closeButton.toolTip = "Remove"

        let label = NSTextField(labelWithString: item.displayName)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2

        addSubview(imageView)
        addSubview(closeButton)
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 78),
            heightAnchor.constraint(equalToConstant: 92),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
            closeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6)
        ])

        Task { [weak imageView] in
            guard let thumbnail = await StashPreviewImageProvider.thumbnail(for: item, size: 48) else { return }
            imageView?.image = thumbnail
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func removeClicked(_ sender: Any?) {
        removeHandler()
    }
}

private func centeredDraggingFrame(for image: NSImage, in bounds: NSRect) -> NSRect {
    guard image.size.width > 0, image.size.height > 0 else {
        return bounds
    }
    return NSRect(
        x: bounds.midX - image.size.width / 2,
        y: bounds.midY - image.size.height / 2,
        width: image.size.width,
        height: image.size.height
    )
}

@MainActor
private enum StashPreviewImageProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: StashItem) -> NSImage {
        guard let url = item.url else {
            return AppIconProvider.image(.file, accessibilityDescription: item.displayName) ?? NSImage()
        }
        return FileIconProvider.icon(for: fileItem(for: item, url: url), size: 64)
    }

    static func thumbnail(for item: StashItem, size: CGFloat) async -> NSImage? {
        guard let url = item.url else { return nil }
        let cacheKey = "\(url.path)-\(Int(size))"
        if let image = cache[cacheKey] {
            return image
        }

        let image = await FileThumbnailProvider.thumbnail(for: fileItem(for: item, url: url), size: size)
        if let image {
            cache[cacheKey] = image
        }
        return image
    }

    private static func fileItem(for item: StashItem, url: URL) -> FileItem {
        FileItem(
            url: url,
            name: item.displayName,
            isDirectory: false,
            size: nil,
            modificationDate: nil,
            creationDate: nil,
            typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier,
            isHidden: url.lastPathComponent.hasPrefix(".")
        )
    }
}

private extension NSPasteboard {
    var canReadStashFileURLs: Bool {
        stashFileURLs?.isEmpty == false
    }

    var stashFileURLs: [URL]? {
        if let urls = fileURLs, !urls.isEmpty {
            return urls
        }

        if let items = pasteboardItems {
            let urls = items.compactMap { item -> URL? in
                if let string = item.string(forType: .fileURL),
                   let url = URL(string: string),
                   url.isFileURL {
                    return url
                }
                if let string = item.string(forType: .URL),
                   let url = URL(string: string),
                   url.isFileURL {
                    return url
                }
                return nil
            }
            if !urls.isEmpty {
                return urls
            }
        }

        if let strings = propertyList(forType: .fileURL) as? [String] {
            let urls = strings.compactMap(URL.init(string:)).filter(\.isFileURL)
            if !urls.isEmpty {
                return urls
            }
        }

        if let strings = propertyList(forType: .URL) as? [String] {
            let urls = strings.compactMap(URL.init(string:)).filter(\.isFileURL)
            if !urls.isEmpty {
                return urls
            }
        }

        return nil
    }
}
