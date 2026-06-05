import AppKit

struct MacPaywallConfiguration {
    let title: String
    let unlockedTitle: String
    let failureTitle: String
    let emptyProductsMessage: String
    let benefits: [String]
    let laterTitle: String
    let okTitle: String
    let launchingPurchaseTitle: String
}

struct MacPaywallProduct: Identifiable {
    let productID: String
    let title: String
    let subtitle: String
    let originalPrice: String?
    let currentPrice: String
    let badge: String?

    var id: String { productID }
}

@MainActor
final class MacPaywallPresenter {
    private let configuration: MacPaywallConfiguration
    private let productsProvider: () async -> [MacPaywallProduct]
    private let isUnlocked: () -> Bool
    private let purchaseHandler: (_ productID: String, _ window: NSWindow?) async throws -> Bool
    private var windowController: NSWindowController?
    private weak var productsStackView: NSStackView?
    private weak var statusLabel: NSTextField?
    private weak var progressIndicator: NSProgressIndicator?

    init(
        configuration: MacPaywallConfiguration,
        productsProvider: @escaping () async -> [MacPaywallProduct],
        isUnlocked: @escaping () -> Bool,
        purchaseHandler: @escaping (_ productID: String, _ window: NSWindow?) async throws -> Bool
    ) {
        self.configuration = configuration
        self.productsProvider = productsProvider
        self.isUnlocked = isUnlocked
        self.purchaseHandler = purchaseHandler
    }

    func show() {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = configuration.title
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView(for: window)
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { await loadProducts() }
    }

    private func makeContentView(for window: NSWindow) -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: configuration.title)
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        let benefitsStack = NSStackView()
        benefitsStack.orientation = .vertical
        benefitsStack.spacing = 8
        benefitsStack.alignment = .leading
        for benefit in configuration.benefits {
            benefitsStack.addArrangedSubview(makeBenefitRow(benefit))
        }

        let productsStack = NSStackView()
        productsStack.orientation = .vertical
        productsStack.spacing = 10
        productsStack.alignment = .width
        self.productsStackView = productsStack

        let statusLabel = NSTextField(labelWithString: configuration.launchingPurchaseTitle)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        self.statusLabel = statusLabel

        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.startAnimation(nil)
        self.progressIndicator = progressIndicator

        let laterButton = NSButton(title: configuration.laterTitle, target: nil, action: nil)
        laterButton.bezelStyle = .rounded
        laterButton.target = self
        laterButton.action = #selector(closeWindow(_:))

        let contentStack = NSStackView(views: [
            titleLabel,
            benefitsStack,
            productsStack,
            progressIndicator,
            statusLabel,
            laterButton
        ])
        contentStack.orientation = .vertical
        contentStack.spacing = 18
        contentStack.alignment = .width
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),
            laterButton.widthAnchor.constraint(equalToConstant: 120)
        ])

        return root
    }

    private func makeBenefitRow(_ benefit: String) -> NSView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        imageView.contentTintColor = .systemGreen
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: benefit)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16)
        ])
        return stack
    }

    private func loadProducts() async {
        guard !isUnlocked() else {
            showStatus(configuration.unlockedTitle, isLoading: false)
            return
        }

        showStatus(configuration.launchingPurchaseTitle, isLoading: true)
        let products = await productsProvider()
        progressIndicator?.stopAnimation(nil)
        progressIndicator?.isHidden = true

        guard !products.isEmpty else {
            showStatus(configuration.emptyProductsMessage, isLoading: false)
            return
        }

        statusLabel?.stringValue = ""
        productsStackView?.arrangedSubviews.forEach { view in
            productsStackView?.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for product in products {
            productsStackView?.addArrangedSubview(makeProductButton(for: product))
        }
    }

    private func makeProductButton(for product: MacPaywallProduct) -> NSButton {
        let titleParts = [
            product.title,
            product.currentPrice,
            product.badge
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        let button = NSButton(title: titleParts.joined(separator: " - "), target: nil, action: nil)
        button.bezelStyle = .rounded
        button.alignment = .center
        button.toolTip = product.subtitle
        button.target = self
        button.action = #selector(purchaseProduct(_:))
        button.identifier = NSUserInterfaceItemIdentifier(product.productID)
        return button
    }

    @objc private func purchaseProduct(_ sender: NSButton) {
        guard let productID = sender.identifier?.rawValue else { return }
        setProductButtonsEnabled(false)
        showStatus(configuration.launchingPurchaseTitle, isLoading: true)

        Task {
            do {
                let unlocked = try await purchaseHandler(productID, windowController?.window)
                showStatus(unlocked ? configuration.unlockedTitle : configuration.failureTitle, isLoading: false)
                if unlocked {
                    productsStackView?.isHidden = true
                } else {
                    setProductButtonsEnabled(true)
                }
            } catch {
                let message = error.localizedDescription.isEmpty ? configuration.failureTitle : error.localizedDescription
                showStatus(message, isLoading: false)
                setProductButtonsEnabled(true)
            }
        }
    }

    private func setProductButtonsEnabled(_ isEnabled: Bool) {
        productsStackView?.arrangedSubviews.forEach { view in
            (view as? NSControl)?.isEnabled = isEnabled
        }
    }

    private func showStatus(_ text: String, isLoading: Bool) {
        statusLabel?.stringValue = text
        progressIndicator?.isHidden = !isLoading
        if isLoading {
            progressIndicator?.startAnimation(nil)
        } else {
            progressIndicator?.stopAnimation(nil)
        }
    }

    @objc private func closeWindow(_ sender: Any?) {
        windowController?.close()
    }
}
