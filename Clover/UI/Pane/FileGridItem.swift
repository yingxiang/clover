import AppKit
import OSLog

final class FileGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileGridItem")

    var renameHandler: ((FileGridItem, String, Bool, Int?) -> Void)?

    private let iconSelectionView = NSView()
    private let iconView = NSImageView()
    private let nameSelectionView = NSView()
    private let tagDotView = FileTagDotView()
    private let nameField = GridNameTextField()
    private let detailField = NSTextField(labelWithString: "")
    private var nameLeadingToTagConstraint: NSLayoutConstraint?
    private var nameLeadingWithoutTagConstraint: NSLayoutConstraint?
    private var representedURL: URL?
    private var representedItemName = ""
    private var representedItemIsDirectory = false
    private var thumbnailTask: Task<Void, Never>?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        iconSelectionView.wantsLayer = true
        iconSelectionView.layer?.cornerRadius = 6
        iconSelectionView.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameSelectionView.wantsLayer = true
        nameSelectionView.layer?.cornerRadius = 5
        nameSelectionView.translatesAutoresizingMaskIntoConstraints = false

        nameField.alignment = .center
        nameField.lineBreakMode = .byWordWrapping
        nameField.maximumNumberOfLines = 2
        nameField.font = .systemFont(ofSize: 12)
        nameField.setContentHuggingPriority(.required, for: .horizontal)
        nameField.setContentHuggingPriority(.required, for: .vertical)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.required, for: .vertical)
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.clickedWhileSelectedHandler = { [weak self] in
            guard self?.isSelected == true else { return false }
            self?.beginEditingName()
            return true
        }

        detailField.alignment = .center
        detailField.lineBreakMode = .byTruncatingTail
        detailField.maximumNumberOfLines = 2
        detailField.textColor = .systemBlue
        detailField.font = .systemFont(ofSize: 10)
        detailField.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconSelectionView)
        view.addSubview(iconView)
        view.addSubview(nameSelectionView)
        nameSelectionView.addSubview(tagDotView)
        nameSelectionView.addSubview(nameField)
        view.addSubview(detailField)

        let nameWithTag = nameField.leadingAnchor.constraint(equalTo: tagDotView.trailingAnchor, constant: 4)
        let nameWithoutTag = nameField.leadingAnchor.constraint(equalTo: nameSelectionView.leadingAnchor, constant: 4)
        nameLeadingToTagConstraint = nameWithTag
        nameLeadingWithoutTagConstraint = nameWithoutTag

        NSLayoutConstraint.activate([
            iconSelectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            iconSelectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconSelectionView.widthAnchor.constraint(equalToConstant: 60),
            iconSelectionView.heightAnchor.constraint(equalToConstant: 58),

            iconView.centerXAnchor.constraint(equalTo: iconSelectionView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconSelectionView.centerYAnchor),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

            nameSelectionView.topAnchor.constraint(equalTo: iconSelectionView.bottomAnchor, constant: 4),
            nameSelectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameSelectionView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 4),
            nameSelectionView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -4),
            nameSelectionView.widthAnchor.constraint(lessThanOrEqualToConstant: 96),

            tagDotView.leadingAnchor.constraint(equalTo: nameSelectionView.leadingAnchor, constant: 5),
            tagDotView.topAnchor.constraint(equalTo: nameSelectionView.topAnchor, constant: 5),
            tagDotView.widthAnchor.constraint(equalToConstant: 8),
            tagDotView.heightAnchor.constraint(equalToConstant: 8),

            nameWithoutTag,
            nameField.trailingAnchor.constraint(equalTo: nameSelectionView.trailingAnchor, constant: -4),
            nameField.topAnchor.constraint(equalTo: nameSelectionView.topAnchor, constant: 1),
            nameField.bottomAnchor.constraint(equalTo: nameSelectionView.bottomAnchor, constant: -1),
            nameField.heightAnchor.constraint(lessThanOrEqualToConstant: 31),

            detailField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            detailField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            detailField.topAnchor.constraint(equalTo: nameSelectionView.bottomAnchor, constant: 0),
            detailField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4)
        ])
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        representedURL = nil
        representedItemName = ""
        representedItemIsDirectory = false
        iconView.image = nil
        nameField.stringValue = ""
        tagDotView.labelNumber = nil
        detailField.stringValue = ""
        nameField.endEditingMode()
    }

    func configure(
        with item: FileItem,
        detail: String,
        directoryAccessStore: DirectoryAccessStore? = nil,
        loadDetailIfNeeded: ((@escaping (String) -> Void) -> Void)? = nil
    ) {
        thumbnailTask?.cancel()
        representedURL = item.url
        representedItemName = item.name
        representedItemIsDirectory = item.isDirectory
        iconView.image = FileIconProvider.icon(for: item, size: 56)
        nameField.stringValue = item.name
        setLabelNumber(item.labelNumber)
        nameField.preferredMaxLayoutWidth = 88
        detailField.stringValue = detail
        view.toolTip = item.name
        updateSelectionAppearance()

        thumbnailTask = Task { [weak self] in
            guard let thumbnail = await FileThumbnailProvider.thumbnail(for: item, size: 56, directoryAccessStore: directoryAccessStore), !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.representedURL == item.url else { return }
                self?.iconView.image = thumbnail
            }
        }

        loadDetailIfNeeded? { [weak self] resolvedDetail in
            guard self?.representedURL == item.url else { return }
            self?.detailField.stringValue = resolvedDetail
        }
    }

    func beginEditingName() {
        nameField.beginEditingMode()
        view.window?.makeFirstResponder(nameField)
        DispatchQueue.main.async { [weak self] in
            self?.selectEditableNameStem()
        }
    }

    var isEditingName: Bool {
        nameField.isEditable && nameField.currentEditor() != nil
    }

    var previewSourceRect: NSRect {
        view.convert(iconSelectionView.frame, to: nil)
    }

    func setDetail(_ detail: String) {
        detailField.stringValue = detail
    }

    private func setLabelNumber(_ labelNumber: Int?) {
        tagDotView.labelNumber = labelNumber
        let hasTag = !tagDotView.isHidden
        nameLeadingToTagConstraint?.isActive = hasTag
        nameLeadingWithoutTagConstraint?.isActive = !hasTag
        nameField.alignment = hasTag ? .left : .center
    }

    private func updateSelectionAppearance() {
        iconSelectionView.layer?.backgroundColor = isSelected ? NSColor.systemGray.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        nameSelectionView.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        nameField.textColor = isSelected ? .selectedTextColor : .labelColor
        nameField.drawsBackground = false
    }

    private func selectEditableNameStem() {
        guard let editor = nameField.currentEditor() else { return }
        editor.selectedRange = editableFileNameSelectionRange(
            for: representedItemName,
            isDirectory: representedItemIsDirectory
        )
    }
}

extension FileGridItem: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ notification: Notification) {
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        let didCancel = movement == NSCancelTextMovement
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.ui.debug("grid controlTextDidEndEditing value=\(newName, privacy: .public) didCancel=\(didCancel) movement=\(movement ?? -1)")
        nameField.endEditingMode()
        updateSelectionAppearance()
        renameHandler?(self, newName, didCancel, movement)
    }
}

private final class GridNameTextField: NSTextField {
    var clickedWhileSelectedHandler: (() -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = nil
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func mouseDown(with event: NSEvent) {
        if !isEditable {
            if clickedWhileSelectedHandler?() == true {
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let collectionView = enclosingCollectionView {
            collectionView.rightMouseDown(with: event)
            return
        }
        super.rightMouseDown(with: event)
    }

    func beginEditingMode() {
        isEditable = true
        isSelectable = true
        isBordered = true
        drawsBackground = true
        maximumNumberOfLines = 1
    }

    func endEditingMode() {
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        maximumNumberOfLines = 2
    }

    private var enclosingCollectionView: FileCollectionView? {
        var currentView = superview
        while let view = currentView {
            if let collectionView = view as? FileCollectionView {
                return collectionView
            }
            currentView = view.superview
        }
        return nil
    }
}
