import AppKit
import QuickLookThumbnailing

@MainActor
final class ProStashShelfWindowController: NSWindowController {
    private static let inactiveAlpha: CGFloat = 0.88
    private static let activeAlpha: CGFloat = 1.0

    private let stashShelfStore: StashShelfStore
    private let bookmarkStore: BookmarkStore
    private let surfaceView = StashShelfSurfaceView()
    private var items: [StashItem] = []
    private var listPopover: NSPopover?

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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 132),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = surfaceView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.alphaValue = Self.inactiveAlpha

        super.init(window: window)

        surfaceView.closeHandler = { [weak self] in self?.window?.close() }
        surfaceView.clearHandler = { [weak self] in self?.clearStash() }
        surfaceView.dropHandler = { [weak self] draggingInfo in
            self?.acceptStashDrop(draggingInfo) ?? false
        }
        surfaceView.dragPresenceChanged = { [weak self] isInside in
            self?.window?.alphaValue = isInside ? Self.activeAlpha : Self.inactiveAlpha
            self?.surfaceView.setDropHighlight(isInside)
        }
        surfaceView.thumbnailClicked = { [weak self] anchor in
            self?.toggleListPopover(anchor: anchor)
        }
        surfaceView.dragItemsProvider = { [weak self] in
            self?.stashedPasteboardItems() ?? []
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
            } else {
                popover.contentViewController = StashShelfListViewController(items: items) { [weak self] item in
                    self?.removeStashItem(item)
                }
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
        window?.alphaValue = Self.inactiveAlpha
        surfaceView.setDropHighlight(false)
        refresh()
        return true
    }

    private func toggleListPopover(anchor: NSView) {
        guard !items.isEmpty else { return }
        if let popover = listPopover, popover.isShown {
            popover.performClose(nil)
            listPopover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = StashShelfListViewController(items: items) { [weak self] item in
            self?.removeStashItem(item)
        }
        listPopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private func removeStashItem(_ item: StashItem) {
        try? stashShelfStore.removeItem(id: item.id)
        refresh()
    }

    private func clearStash() {
        try? stashShelfStore.clear()
        refresh()
    }

    private func stashedPasteboardItems() -> [any NSPasteboardWriting] {
        items.compactMap { item in
            guard let url = item.url else { return nil }
            return url as NSURL
        }
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
}

private final class StashShelfSurfaceView: NSView {
    var closeHandler: (() -> Void)?
    var clearHandler: (() -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?
    var dragPresenceChanged: ((Bool) -> Void)?
    var thumbnailClicked: ((NSView) -> Void)?
    var dragItemsProvider: (() -> [any NSPasteboardWriting])?

    private let glassView = NSVisualEffectView()
    private let plusImageView = NSImageView()
    private let thumbnailStackView = StashThumbnailStackView()
    private let moveButton = StashShelfMoveButton(symbolName: "arrow.up.and.down.and.arrow.left.and.right", pointSize: 11)
    private let countBadgeView = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private var hasItems = false
    private var items: [StashItem] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(items: [StashItem]) {
        self.items = items
        let isEmpty = items.isEmpty
        hasItems = !isEmpty
        glassView.isHidden = false
        glassView.alphaValue = isEmpty ? 1 : 0.42
        plusImageView.isHidden = !isEmpty
        thumbnailStackView.isHidden = isEmpty
        countBadgeView.isHidden = isEmpty
        countLabel.stringValue = "\(items.count)"
        updateBorder(isDropTargeted: false)
        thumbnailStackView.configure(items: items)
    }

    func setDropHighlight(_ isDropTargeted: Bool) {
        updateBorder(isDropTargeted: isDropTargeted)
        glassView.alphaValue = isDropTargeted ? 0.72 : (hasItems ? 0.42 : 1)
    }

    private func setup() {
        registerForDraggedTypes([.fileURL, .URL])
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerRadius = 30

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.material = .hudWindow
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 28
        glassView.layer?.borderWidth = 0.8
        glassView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
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
        thumbnailStackView.menuProvider = { [weak self] in
            self?.contextMenu()
        }
        addSubview(thumbnailStackView)

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
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            glassView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            plusImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            plusImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            plusImageView.widthAnchor.constraint(equalToConstant: 44),
            plusImageView.heightAnchor.constraint(equalToConstant: 44),

            thumbnailStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailStackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 4),
            thumbnailStackView.widthAnchor.constraint(equalToConstant: 94),
            thumbnailStackView.heightAnchor.constraint(equalToConstant: 78),

            moveButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            moveButton.centerXAnchor.constraint(equalTo: centerXAnchor),
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
        let clearItem = NSMenuItem(title: "清空暂存架", action: #selector(clearClicked(_:)), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = hasItems
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭窗口", action: #selector(closeClicked(_:)), keyEquivalent: "")
        closeItem.target = self; menu.addItem(closeItem)
        return menu
    }

    @objc private func clearClicked(_ sender: Any?) {
        clearHandler?()
    }

    @objc private func closeClicked(_ sender: Any?) {
        closeHandler?()
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
        guard hasItems || isDropTargeted else {
            glassView.layer?.borderWidth = 0.8
            glassView.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            layer?.shadowOpacity = 0
            return
        }
        glassView.layer?.borderWidth = isDropTargeted ? 2 : 1.25
        glassView.layer?.borderColor = (isDropTargeted ? NSColor.controlAccentColor : NSColor.white)
            .withAlphaComponent(isDropTargeted ? 0.95 : 0.78)
            .cgColor
        layer?.shadowColor = (isDropTargeted ? NSColor.controlAccentColor : NSColor.clear).cgColor
        layer?.shadowOpacity = isDropTargeted ? 0.75 : 0
        layer?.shadowRadius = isDropTargeted ? 14 : 0
        layer?.shadowOffset = .zero
    }

}

private final class StashThumbnailStackView: NSView {
    var clickHandler: ((NSView) -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?
    var dragPresenceChanged: ((Bool) -> Void)?
    var dragItemsProvider: (() -> [any NSPasteboardWriting])?
    var menuProvider: (() -> NSMenu?)?

    private var mouseDownEvent: NSEvent?
    private var didBeginFileDrag = false

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
            imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            imageView.layer?.cornerRadius = 10
            imageView.layer?.borderWidth = 1
            imageView.layer?.borderColor = NSColor.separatorColor.cgColor
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
                imageView.widthAnchor.constraint(equalToConstant: 64),
                imageView.heightAnchor.constraint(equalToConstant: 64)
            ])
            Task { [weak imageView] in
                guard let thumbnail = await StashPreviewImageProvider.thumbnail(for: item, size: 64) else { return }
                imageView?.image = thumbnail
            }
        }
    }

    private static func stackLayout(for count: Int) -> [(x: CGFloat, y: CGFloat, rotation: CGFloat)] {
        switch count {
        case 0, 1:
            return [(0, 0, 0)]
        case 2:
            return [(-6, 3, -4), (8, -4, 5)]
        case 3:
            return [(-12, 6, -7), (0, 0, -1), (12, -6, 6)]
        default:
            return [(-16, 8, -8), (-5, 2, -3), (7, -4, 3), (18, -8, 8)]
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didBeginFileDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginFileDrag, let items = dragItemsProvider?(), !items.isEmpty else { return }
        didBeginFileDrag = true
        let snapshot = snapshotImage()
        let draggingItems = items.map { pasteboardWriter in
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
            draggingItem.setDraggingFrame(bounds, contents: snapshot)
            return draggingItem
        }
        beginDraggingSession(with: draggingItems, event: mouseDownEvent ?? event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didBeginFileDrag {
            clickHandler?(self)
        }
        mouseDownEvent = nil
        didBeginFileDrag = false
    }

    private func snapshotImage() -> NSImage {
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
}

extension StashThumbnailStackView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
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
    private let items: [StashItem]
    private let removeHandler: (StashItem) -> Void

    init(items: [StashItem], removeHandler: @escaping (StashItem) -> Void) {
        self.items = items
        self.removeHandler = removeHandler
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: min(520, max(180, items.count * 96 + 24)), height: 112)
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

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        items.forEach { item in
            stackView.addArrangedSubview(StashShelfListItemView(item: item) { [weak self] in
                self?.removeHandler(item)
            })
        }

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
            heightAnchor.constraint(equalToConstant: 82),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
            closeButton.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -2),
            closeButton.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: 2),
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

@MainActor
private enum StashPreviewImageProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: StashItem) -> NSImage {
        guard let url = item.url else {
            return AppIconProvider.image(.file, accessibilityDescription: item.displayName) ?? NSImage()
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 64, height: 64)
        image.accessibilityDescription = item.displayName
        return image
    }

    static func thumbnail(for item: StashItem, size: CGFloat) async -> NSImage? {
        guard let url = item.url else { return nil }
        let cacheKey = "\(url.path)-\(Int(size))"
        if let image = cache[cacheKey] {
            return image
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: NSSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        let image = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
        if let image {
            cache[cacheKey] = image
        }
        return image
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
