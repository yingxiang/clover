import AppKit

@MainActor
final class SupportDeveloperWindowController: NSWindowController {
    init() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: L10n.supportDeveloperWindowTitle)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0

        let subtitleLabel = NSTextField(labelWithString: L10n.tipMe)
        subtitleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor

        let imageView = NSImageView()
        imageView.image = NSImage(named: "alipay")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel(L10n.tipMe)

        let scanHintLabel = NSTextField(labelWithString: L10n.openAlipayScan)
        scanHintLabel.alignment = .center
        scanHintLabel.font = .systemFont(ofSize: 13)
        scanHintLabel.textColor = .secondaryLabelColor

        let stackView = NSStackView(views: [titleLabel, subtitleLabel, imageView, scanHintLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -28),
            titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 300),
            imageView.heightAnchor.constraint(equalToConstant: 300),
            scanHintLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.supportDeveloper
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
