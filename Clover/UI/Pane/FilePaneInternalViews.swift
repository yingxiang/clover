import AppKit

func editableFileNameSelectionRange(for name: String, isDirectory: Bool) -> NSRange {
    guard !isDirectory else {
        return NSRange(location: 0, length: (name as NSString).length)
    }
    let nsName = name as NSString
    let pathExtension = nsName.pathExtension
    guard !pathExtension.isEmpty else {
        return NSRange(location: 0, length: nsName.length)
    }
    let stemLength = max(nsName.length - (pathExtension as NSString).length - 1, 0)
    return NSRange(location: 0, length: stemLength)
}

final class FileTableHeaderView: NSTableHeaderView {
    var typeColumnClickHandler: ((NSTableColumn) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: point)
        guard columnIndex >= 0,
              let tableView,
              tableView.tableColumns[columnIndex].identifier.rawValue == "type" else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(tableView)
        typeColumnClickHandler?(tableView.tableColumns[columnIndex])
    }
}

final class FileListNameCellView: NSTableCellView {
    let disclosureButton = NSButton()
    let fileIconView = NSImageView()
    let nameTextField = FileListNameTextField(string: "")
    private let tagDotView = FileTagDotView()
    private var disclosureLeadingConstraint: NSLayoutConstraint?
    private var nameTrailingToTagConstraint: NSLayoutConstraint?
    private var nameTrailingWithoutTagConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        guard textField == nil else { return }
        disclosureButton.isBordered = false
        disclosureButton.imagePosition = .imageOnly
        disclosureButton.setButtonType(.momentaryChange)
        disclosureButton.translatesAutoresizingMaskIntoConstraints = false

        fileIconView.imageScaling = .scaleProportionallyUpOrDown
        fileIconView.translatesAutoresizingMaskIntoConstraints = false

        nameTextField.isBordered = false
        nameTextField.isEditable = true
        nameTextField.isSelectable = true
        nameTextField.drawsBackground = false
        nameTextField.lineBreakMode = .byTruncatingMiddle
        nameTextField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(disclosureButton)
        addSubview(fileIconView)
        addSubview(nameTextField)
        addSubview(tagDotView)
        imageView = fileIconView
        textField = nameTextField

        let leading = disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        disclosureLeadingConstraint = leading
        let nameTrailingToTag = nameTextField.trailingAnchor.constraint(lessThanOrEqualTo: tagDotView.leadingAnchor, constant: -5)
        let nameTrailingWithoutTag = nameTextField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6)
        nameTrailingToTagConstraint = nameTrailingToTag
        nameTrailingWithoutTagConstraint = nameTrailingWithoutTag
        NSLayoutConstraint.activate([
            leading,
            disclosureButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosureButton.widthAnchor.constraint(equalToConstant: 14),
            disclosureButton.heightAnchor.constraint(equalToConstant: 18),
            fileIconView.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 4),
            fileIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileIconView.widthAnchor.constraint(equalToConstant: 18),
            fileIconView.heightAnchor.constraint(equalToConstant: 18),
            nameTextField.leadingAnchor.constraint(equalTo: fileIconView.trailingAnchor, constant: 6),
            nameTrailingWithoutTag,
            nameTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            tagDotView.centerYAnchor.constraint(equalTo: nameTextField.centerYAnchor),
            tagDotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            tagDotView.widthAnchor.constraint(equalToConstant: 8),
            tagDotView.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    func configureDisclosure(depth: Int, canExpand: Bool, isExpanded: Bool) {
        disclosureLeadingConstraint?.constant = 6 + CGFloat(depth * 16)
        disclosureButton.isHidden = !canExpand
        let symbolName = isExpanded ? "chevron.down" : "chevron.right"
        disclosureButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    func setLabelNumber(_ labelNumber: Int?) {
        tagDotView.labelNumber = labelNumber
        let hasTag = !tagDotView.isHidden
        nameTrailingToTagConstraint?.isActive = hasTag
        nameTrailingWithoutTagConstraint?.isActive = !hasTag
    }

    var previewSourceRect: NSRect {
        fileIconView.frame.insetBy(dx: -1, dy: -1)
    }

    var previewTransitionImage: NSImage? {
        fileIconView.image
    }
}

final class FileListNameTextField: NSTextField {
    var clickedWhileSelectedHandler: (() -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if currentEditor() == nil,
           clickedWhileSelectedHandler?() == true {
            return
        }
        super.mouseDown(with: event)
    }
}

final class FileTagDotView: NSView {
    var labelNumber: Int? {
        didSet {
            isHidden = FileTagDotView.color(for: labelNumber) == nil
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let color = FileTagDotView.color(for: labelNumber) else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
    }

    static func color(for labelNumber: Int?) -> NSColor? {
        switch labelNumber {
        case 1:
            return .systemGray
        case 2:
            return .systemGreen
        case 3:
            return .systemPurple
        case 4:
            return .systemBlue
        case 5:
            return .systemYellow
        case 6:
            return .systemRed
        case 7:
            return .systemOrange
        default:
            return nil
        }
    }
}

final class FileTableView: NSTableView {
    var activationHandler: (() -> Void)?
    var rightClickHandler: ((Int) -> Void)?
    var dropHandler: ((NSDraggingInfo, Int?) -> Bool)?
    var dragUpdateHandler: ((NSDraggingInfo, Int?) -> NSDragOperation)?
    var dragExitHandler: (() -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        activationHandler?()
        let point = convert(event.locationInWindow, from: nil)
        if row(at: point) < 0 {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        activationHandler?()
        let point = convert(event.locationInWindow, from: nil)
        rightClickHandler?(row(at: point))
        super.rightMouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragExitHandler?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dragExitHandler?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let row = row(at: point)
        return dropHandler?(sender, row >= 0 ? row : nil) ?? false
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    private func updateDragTarget(for sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let row = row(at: point)
        return dragUpdateHandler?(sender, row >= 0 ? row : nil)
            ?? (sender.draggingPasteboard.canReadFileURLs ? .move : [])
    }
}

final class FileCollectionView: NSCollectionView {
    var activationHandler: (() -> Void)?
    var rightClickHandler: ((Int?) -> Void)?
    var dropHandler: ((NSDraggingInfo, Int?) -> Bool)?
    var dragUpdateHandler: ((NSDraggingInfo, Int?) -> NSDragOperation)?
    var dragExitHandler: (() -> Void)?
    var doubleClickHandler: ((Int) -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        activationHandler?()
        let point = convert(event.locationInWindow, from: nil)
        if indexPathForItem(at: point) == nil {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        guard let index = indexPathForItem(at: point)?.item else { return }
        doubleClickHandler?(index)
    }

    override func rightMouseDown(with event: NSEvent) {
        activationHandler?()
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        rightClickHandler?(indexPathForItem(at: point)?.item)
        super.rightMouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragExitHandler?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dragExitHandler?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let index = indexPathForItem(at: point)?.item
        return dropHandler?(sender, index) ?? false
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    private func updateDragTarget(for sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let index = indexPathForItem(at: point)?.item
        return dragUpdateHandler?(sender, index)
            ?? (sender.draggingPasteboard.canReadFileURLs ? .move : [])
    }
}

final class FileDropScrollView: NSScrollView {
    var activationHandler: (() -> Void)?
    var rightClickHandler: (() -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?
    var dragUpdateHandler: ((NSDraggingInfo) -> NSDragOperation)?
    var dragExitHandler: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        activationHandler?()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        activationHandler?()
        rightClickHandler?()
        super.rightMouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragUpdateHandler?(sender) ?? (sender.draggingPasteboard.canReadFileURLs ? .move : [])
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragUpdateHandler?(sender) ?? (sender.draggingPasteboard.canReadFileURLs ? .move : [])
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragExitHandler?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dragExitHandler?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandler?(sender) ?? false
    }
}

final class EventMonitorToken: @unchecked Sendable {
    private let monitor: Any

    init(_ monitor: Any) {
        self.monitor = monitor
    }

    @MainActor
    func remove() {
        NSEvent.removeMonitor(monitor)
    }
}

extension NSPasteboard.PasteboardType {
    static let cloverPaneDragSourceIdentifier = NSPasteboard.PasteboardType("com.lingchen.clover.drag-source-pane")
    static let cloverFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
}

struct CloverPasteboardFile {
    let url: URL
    let isDirectory: Bool

    var dragURL: URL {
        URL(fileURLWithPath: url.path, isDirectory: isDirectory).standardizedFileURL
    }

    func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let dragURL = dragURL
        item.setString(dragURL.absoluteString, forType: .fileURL)
        item.setString(dragURL.absoluteString, forType: .URL)
        item.setString(dragURL.path, forType: .string)
        item.setPropertyList([dragURL.path], forType: .cloverFilenames)
        return item
    }
}

extension NSPasteboard {
    var canReadFileURLs: Bool {
        fileURLs?.isEmpty == false
    }

    @discardableResult
    func writeCloverFileDragItems(_ files: [CloverPasteboardFile], sourceIdentifier: String? = nil) -> Bool {
        let urls = files.map(\.dragURL)
        guard !urls.isEmpty else { return false }
        clearContents()
        let didWrite = writeObjects(urls.map { $0 as NSURL })
        let paths = urls.map(\.path)
        setPropertyList(paths, forType: .cloverFilenames)
        setPropertyList(urls.map(\.absoluteString), forType: .fileURL)
        setPropertyList(urls.map(\.absoluteString), forType: .URL)
        setString(paths.joined(separator: "\n"), forType: .string)
        if let sourceIdentifier {
            setString(sourceIdentifier, forType: .cloverPaneDragSourceIdentifier)
        }
        return didWrite
    }

    var fileURLs: [URL]? {
        if let urls = readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL], !urls.isEmpty {
            return urls.map { $0 as URL }
        }

        if let fileURLStrings = propertyList(forType: .fileURL) as? [String] {
            let urls = fileURLStrings.compactMap(URL.init(string:)).filter(\.isFileURL)
            if !urls.isEmpty { return urls }
        }

        if let fileURLString = string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL {
            return [url]
        }

        if let urlStrings = propertyList(forType: .URL) as? [String] {
            let urls = urlStrings.compactMap(URL.init(string:)).filter(\.isFileURL)
            if !urls.isEmpty { return urls }
        }

        if let urlString = string(forType: .URL),
           let url = URL(string: urlString),
           url.isFileURL {
            return [url]
        }

        return nil
    }
}

extension NSEvent {
    var nonNavigationModifierFlags: NSEvent.ModifierFlags {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function])
    }
}
