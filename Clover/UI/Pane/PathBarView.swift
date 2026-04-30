import AppKit

final class PathBarView: NSView, NSTextFieldDelegate {
    var navigationHandler: ((URL) -> Void)?
    var pathSubmitHandler: ((String) -> Void)?

    private let stackView = NSStackView()
    private let pathField = NSTextField()
    private var currentURL = FileManager.default.homeDirectoryForCurrentUser

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(url: URL) {
        currentURL = url
        pathField.stringValue = displayPath(for: url)
        rebuildBreadcrumbs(for: url)
    }

    func beginEditing() {
        pathField.stringValue = displayPath(for: currentURL)
        stackView.isHidden = true
        pathField.isHidden = false
        window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if !stackView.frame.contains(location), !pathField.frame.contains(location) {
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
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        pathField.isHidden = true
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.font = .systemFont(ofSize: 12)
        pathField.target = self
        pathField.action = #selector(submitPath(_:))
        pathField.delegate = self
        pathField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pathField)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            pathField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            pathField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func rebuildBreadcrumbs(for url: URL) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, crumb) in breadcrumbs(for: url).enumerated() {
            if index > 0 {
                let separator = NSTextField(labelWithString: "/")
                separator.textColor = .secondaryLabelColor
                separator.font = .systemFont(ofSize: 11)
                stackView.addArrangedSubview(separator)
            }

            let button = PathBreadcrumbButton(title: crumb.title, target: self, action: #selector(openBreadcrumb(_:)))
            button.bezelStyle = .inline
            button.isBordered = false
            button.font = .systemFont(ofSize: 12)
            button.contentTintColor = crumb.url == url ? .labelColor : .controlAccentColor
            button.toolTip = crumb.url.path
            button.url = crumb.url
            stackView.addArrangedSubview(button)
        }
    }

    @objc private func openBreadcrumb(_ sender: PathBreadcrumbButton) {
        navigationHandler?(sender.url)
    }

    private func finishEditing() {
        pathField.isHidden = true
        stackView.isHidden = false
    }

    private func breadcrumbs(for url: URL) -> [(title: String, url: URL)] {
        let components = url.standardizedFileURL.pathComponents
        guard !components.isEmpty else { return [(title: "/", url: URL(fileURLWithPath: "/", isDirectory: true))] }

        var crumbs: [(title: String, url: URL)] = []
        var path = ""
        for component in components {
            if component == "/" {
                path = "/"
                crumbs.append((title: rootTitle(), url: URL(fileURLWithPath: "/", isDirectory: true)))
                continue
            }

            path = (path as NSString).appendingPathComponent(component)
            crumbs.append((title: component, url: URL(fileURLWithPath: path, isDirectory: true)))
        }
        return crumbs
    }

    private func rootTitle() -> String {
        FileManager.default.displayName(atPath: "/").isEmpty ? "/" : FileManager.default.displayName(atPath: "/")
    }

    private func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private final class PathBreadcrumbButton: NSButton {
    var url = URL(fileURLWithPath: "/", isDirectory: true)
}
