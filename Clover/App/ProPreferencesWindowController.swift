import AppKit

@MainActor
final class ProPreferencesWindowController: NSWindowController {
    private let toolbarPreferencesStore: ToolbarPreferencesStore
    private let onToolbarPreferencesChanged: () -> Void

    private let shortcutTitles = [
        L10n.refresh,
        L10n.goToFolder,
        L10n.rename,
        L10n.copyTo,
        L10n.moveTo,
        L10n.moveToTrash
    ]
    private var shortcutFields: [String: NSTextField] = [:]

    init(toolbarPreferencesStore: ToolbarPreferencesStore, onToolbarPreferencesChanged: @escaping () -> Void) {
        self.toolbarPreferencesStore = toolbarPreferencesStore
        self.onToolbarPreferencesChanged = onToolbarPreferencesChanged

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: L10n.proCustomToolbar)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: L10n.proCustomToolbarSubtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 0

        let shortcutFields: [String: NSTextField] = [
            L10n.refresh: NSTextField(),
            L10n.goToFolder: NSTextField(),
            L10n.rename: NSTextField(),
            L10n.copyTo: NSTextField(),
            L10n.moveTo: NSTextField(),
            L10n.moveToTrash: NSTextField()
        ]
        self.shortcutFields = shortcutFields

        let toolbarStack = NSStackView()
        toolbarStack.orientation = .vertical
        toolbarStack.alignment = .leading
        toolbarStack.spacing = 8
        var toolbarButtons: [NSButton] = []
        for item in ToolbarPreferencesStore.Item.allCases {
            let box = NSButton(checkboxWithTitle: item.rawValue.capitalized, target: nil, action: nil)
            box.state = toolbarPreferencesStore.isVisible(item) ? .on : .off
            box.tag = ToolbarPreferencesStore.Item.allCases.firstIndex(of: item) ?? 0
            toolbarStack.addArrangedSubview(box)
            toolbarButtons.append(box)
        }

        let shortcutTitleLabel = NSTextField(labelWithString: L10n.proAdvancedShortcuts)
        shortcutTitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let shortcutSubtitleLabel = NSTextField(labelWithString: L10n.proAdvancedShortcutsSubtitle)
        shortcutSubtitleLabel.font = .systemFont(ofSize: 13)
        shortcutSubtitleLabel.textColor = .secondaryLabelColor
        shortcutSubtitleLabel.lineBreakMode = .byWordWrapping
        shortcutSubtitleLabel.maximumNumberOfLines = 0

        let shortcutGrid = NSGridView(views: shortcutTitles.map { title in
            let field = shortcutFields[title]!
            field.placeholderString = "⌘R"
            return [Self.label(title), field]
        })
        shortcutGrid.rowSpacing = 8
        shortcutGrid.columnSpacing = 12

        let saveButton = NSButton(title: L10n.save, target: nil, action: nil)
        let stack = NSStackView(views: [titleLabel, subtitleLabel, toolbarStack, shortcutTitleLabel, shortcutSubtitleLabel, shortcutGrid, saveButton])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.proCustomToolbar
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        for button in toolbarButtons {
            button.target = self
            button.action = #selector(toggleToolbarItem(_:))
        }
        saveButton.target = self
        saveButton.action = #selector(savePreferences(_:))
        for title in shortcutTitles {
            shortcutFields[title]?.stringValue = currentShortcut(for: title)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleToolbarItem(_ sender: NSButton) {
        guard let item = ToolbarPreferencesStore.Item.allCases[safe: sender.tag] else { return }
        toolbarPreferencesStore.setVisible(item, visible: sender.state == .on)
        onToolbarPreferencesChanged()
    }

    @objc private func savePreferences(_ sender: Any?) {
        var mapping: [String: String] = [:]
        for (title, field) in shortcutFields {
            let shortcut = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !shortcut.isEmpty {
                mapping[title] = shortcut
            }
        }
        UserDefaults.standard.set(mapping, forKey: "NSUserKeyEquivalents")
        onToolbarPreferencesChanged()
    }

    private func currentShortcut(for title: String) -> String {
        let mapping = UserDefaults.standard.dictionary(forKey: "NSUserKeyEquivalents") as? [String: String]
        return mapping?[title] ?? ""
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
