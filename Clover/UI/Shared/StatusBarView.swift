import AppKit

final class StatusBarView: NSView {
    private let label = NSTextField(labelWithString: String(localized: "ready", defaultValue: "Ready"))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setText(_ text: String) {
        label.stringValue = text
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        label.textColor = .secondaryLabelColor
    }
}
