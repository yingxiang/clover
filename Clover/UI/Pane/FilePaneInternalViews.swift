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
    let nameTextField = NSTextField(string: "")
    private var disclosureLeadingConstraint: NSLayoutConstraint?

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
        imageView = fileIconView
        textField = nameTextField

        let leading = disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        disclosureLeadingConstraint = leading
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
            nameTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configureDisclosure(depth: Int, canExpand: Bool, isExpanded: Bool) {
        disclosureLeadingConstraint?.constant = 6 + CGFloat(depth * 16)
        disclosureButton.isHidden = !canExpand
        let symbolName = isExpanded ? "chevron.down" : "chevron.right"
        disclosureButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    var previewSourceRect: NSRect {
        fileIconView.frame.insetBy(dx: -1, dy: -1)
    }

    var previewTransitionImage: NSImage? {
        fileIconView.image
    }
}

final class FileTableView: NSTableView {
    var activationHandler: (() -> Void)?
    var rightClickHandler: ((Int) -> Void)?
    var dropHandler: ((NSDraggingInfo, Int?) -> Bool)?
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
        sender.draggingPasteboard.canReadFileURLs ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadFileURLs ? .move : []
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
}

final class FileCollectionView: NSCollectionView {
    var activationHandler: (() -> Void)?
    var rightClickHandler: ((Int?) -> Void)?
    var dropHandler: ((NSDraggingInfo, Int?) -> Bool)?
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
        sender.draggingPasteboard.canReadFileURLs ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadFileURLs ? .move : []
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
}

final class FileDropScrollView: NSScrollView {
    var activationHandler: (() -> Void)?
    var rightClickHandler: (() -> Void)?
    var dropHandler: ((NSDraggingInfo) -> Bool)?

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
        sender.draggingPasteboard.canReadFileURLs ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadFileURLs ? .move : []
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

extension NSPasteboard {
    var canReadFileURLs: Bool {
        fileURLs?.isEmpty == false
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
