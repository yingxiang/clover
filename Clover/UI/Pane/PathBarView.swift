import AppKit

final class PathBarView: NSView, NSTextFieldDelegate {
    var navigationHandler: ((URL) -> Void)?
    var pathSubmitHandler: ((String) -> Void)?

    private let pathControl = NSPathControl()
    private let pathField = NSTextField()
    private var currentURL = UserDirectories.homeURL

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(url: URL) {
        currentURL = url
        pathControl.url = url
        pathField.stringValue = displayPath(for: url)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func beginEditing() {
        pathField.stringValue = displayPath(for: currentURL)
        pathControl.isHidden = true
        pathField.isHidden = false
        window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let pathFieldContainsClick = !pathField.isHidden && pathField.frame.contains(location)
        if !pathControl.frame.contains(location), !pathFieldContainsClick {
            beginEditing()
            return
        }
        super.mouseDown(with: event)
    }

    @objc private func submitPath(_ sender: NSTextField) {
        let path = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            finishEditing()
            return
        }
        finishEditing()
        pathSubmitHandler?(path)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishEditing()
    }

    private func configureViews() {
        pathControl.pathStyle = .standard
        pathControl.url = currentURL
        pathControl.target = self
        pathControl.action = #selector(openPathComponent(_:))
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        pathControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(pathControl)

        pathField.isHidden = true
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.font = .systemFont(ofSize: 12)
        pathField.target = self
        pathField.action = #selector(submitPath(_:))
        pathField.delegate = self
        pathField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pathField)

        let pathControlTrailingConstraint = pathControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        pathControlTrailingConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            pathControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            pathControlTrailingConstraint,
            pathControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            pathField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            pathField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    @objc private func openPathComponent(_ sender: NSPathControl) {
        guard let url = sender.clickedPathItem?.url ?? sender.url else { return }
        navigationHandler?(url)
    }

    private func finishEditing() {
        pathField.isHidden = true
        pathControl.isHidden = false
    }

    private func updateAppearance() {
        pathField.textColor = .labelColor
        pathField.backgroundColor = .textBackgroundColor
    }

    private func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = UserDirectories.homeURL.standardizedFileURL.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
