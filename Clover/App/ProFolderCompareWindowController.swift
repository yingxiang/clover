import AppKit

@MainActor
final class ProFolderCompareWindowController: NSWindowController {
    private let paneURLsProvider: () -> [URL]
    private let fileProvider: any FileProvider

    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let detailTextView = NSTextView()

    init(paneURLsProvider: @escaping () -> [URL], fileProvider: any FileProvider) {
        self.paneURLsProvider = paneURLsProvider
        self.fileProvider = fileProvider

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: String(localized: "pro_folder_compare", defaultValue: "Folder Compare"))
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: String(localized: "pro_folder_compare_subtitle", defaultValue: "Compare the contents of two panes."))
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 0

        let refreshButton = NSButton(title: String(localized: "refresh", defaultValue: "Refresh"), target: nil, action: nil)

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailTextView.textContainerInset = NSSize(width: 6, height: 6)
        let scrollView = NSScrollView()
        scrollView.documentView = detailTextView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, subtitleLabel, leftLabel, rightLabel, summaryLabel, refreshButton, scrollView])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "pro_folder_compare", defaultValue: "Folder Compare")
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        refreshButton.target = self
        refreshButton.action = #selector(refreshComparison(_:))
        refreshComparison(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func refreshComparison(_ sender: Any?) {
        let urls = paneURLsProvider()
        guard urls.count >= 2 else {
            leftLabel.stringValue = String(localized: "pro_folder_compare_needs_two_panes", defaultValue: "Open at least two panes to compare folders.")
            rightLabel.stringValue = ""
            summaryLabel.stringValue = ""
            detailTextView.string = ""
            return
        }

        let leftURL = urls[0]
        let rightURL = urls[1]
        leftLabel.stringValue = "\(String(localized: "left", defaultValue: "Left")): \(leftURL.path)"
        rightLabel.stringValue = "\(String(localized: "right", defaultValue: "Right")): \(rightURL.path)"
        detailTextView.string = String(localized: "loading", defaultValue: "Loading")

        Task {
            do {
                let leftItems = try await fileProvider.listDirectory(at: leftURL)
                let rightItems = try await fileProvider.listDirectory(at: rightURL)
                let leftNames = Set(leftItems.map(\.name))
                let rightNames = Set(rightItems.map(\.name))
                let shared = leftNames.intersection(rightNames).sorted()
                let onlyLeft = leftNames.subtracting(rightNames).sorted()
                let onlyRight = rightNames.subtracting(leftNames).sorted()
                await MainActor.run {
                    self.summaryLabel.stringValue = String(
                        format: String(localized: "pro_folder_compare_summary", defaultValue: "%lld items on the left, %lld items on the right, %lld shared, %lld only on the left, %lld only on the right."),
                        leftNames.count,
                        rightNames.count,
                        shared.count,
                        onlyLeft.count,
                        onlyRight.count
                    )
                    self.detailTextView.string = [
                        "\(String(localized: "shared", defaultValue: "Shared")):",
                        shared.joined(separator: "\n"),
                        "",
                        "\(String(localized: "left", defaultValue: "Left")) \(String(localized: "only", defaultValue: "Only")):",
                        onlyLeft.joined(separator: "\n"),
                        "",
                        "\(String(localized: "right", defaultValue: "Right")) \(String(localized: "only", defaultValue: "Only")):",
                        onlyRight.joined(separator: "\n")
                    ].joined(separator: "\n")
                }
            } catch {
                await MainActor.run {
                    self.detailTextView.string = error.localizedDescription
                }
            }
        }
    }
}
