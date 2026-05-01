import AppKit

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
