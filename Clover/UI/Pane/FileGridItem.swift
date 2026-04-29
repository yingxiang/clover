import AppKit

final class FileGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileGridItem")

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.maximumNumberOfLines = 2
        nameField.font = .systemFont(ofSize: 12)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconView)
        view.addSubview(nameField)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6)
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor : NSColor.clear.cgColor
            view.layer?.cornerRadius = 6
        }
    }

    func configure(with item: FileItem) {
        iconView.image = FileIconProvider.icon(for: item, size: 48)
        nameField.stringValue = item.name
        view.toolTip = item.name
    }
}
