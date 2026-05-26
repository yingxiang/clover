import AppKit
import StoreKit

@MainActor
final class UpgradeProWindowController: NSWindowController {
    private let entitlementService: EntitlementService
    private let productStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let purchaseButton = NSButton(title: L10n.proBuySelected, target: nil, action: nil)
    private let restoreButton = NSButton(title: L10n.restorePurchases, target: nil, action: nil)
    private let manageButton = NSButton(title: L10n.manageSubscription, target: nil, action: nil)
    private var selectedProductID = ProProduct.lifetime.rawValue

    init(entitlementService: EntitlementService) {
        self.entitlementService = entitlementService

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: L10n.upgradeToPro)
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: L10n.proUpgradeSubtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let featureStack = NSStackView()
        featureStack.orientation = .vertical
        featureStack.alignment = .leading
        featureStack.spacing = 6
        for feature in ProFeature.visibleFeatures {
            featureStack.addArrangedSubview(Self.makeFeatureRow(feature.title))
        }

        productStack.orientation = .vertical
        productStack.alignment = .width
        productStack.spacing = 8

        purchaseButton.bezelStyle = .rounded
        purchaseButton.keyEquivalent = "\r"

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 2

        var actionButtons = [purchaseButton]
#if DEBUG
        actionButtons.append(restoreButton)
        actionButtons.append(manageButton)
#endif
        let buttonStack = NSStackView(views: actionButtons)
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        let stackView = NSStackView(views: [titleLabel, subtitleLabel, featureStack, productStack, buttonStack, statusLabel])
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            subtitleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.upgradeToPro
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        purchaseButton.target = self
        purchaseButton.action = #selector(purchaseSelectedProduct(_:))
#if DEBUG
        restoreButton.target = self
        restoreButton.action = #selector(restorePurchases(_:))
        manageButton.target = self
        manageButton.action = #selector(manageSubscription(_:))
#endif
        renderLoadingState()
        loadProducts()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadProducts() {
        Task { [weak self] in
            guard let self else { return }
            await entitlementService.loadProducts()
            renderProducts()
        }
    }

    private func renderLoadingState() {
        productStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusLabel.stringValue = L10n.proLoadingProducts
        purchaseButton.isEnabled = false
    }

    private func renderProducts() {
        productStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if entitlementService.isProUnlocked {
            statusLabel.stringValue = L10n.proAlreadyUnlocked
            purchaseButton.isEnabled = false
        } else if let error = entitlementService.productLoadError {
            statusLabel.stringValue = error.localizedDescription
            purchaseButton.isEnabled = false
        } else if entitlementService.products.isEmpty {
            statusLabel.stringValue = L10n.proNoProducts
            purchaseButton.isEnabled = false
        } else {
            statusLabel.stringValue = L10n.proSelectPlan
            purchaseButton.isEnabled = true
        }

        for product in entitlementService.products {
            productStack.addArrangedSubview(makeProductButton(for: product))
        }
    }

    private static func makeFeatureRow(_ title: String) -> NSView {
        let icon = NSImageView(image: AppIconProvider.image(.proCheckmark, accessibilityDescription: title) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .systemGreen

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
        return row
    }

    private func makeProductButton(for product: Product) -> NSButton {
        let knownProduct = ProProduct(rawValue: product.id)
        let title = knownProduct?.displayTitle ?? product.displayName
        let subtitle = knownProduct?.displaySubtitle ?? product.description
        let badge = product.id == ProProduct.lifetime.rawValue ? "  \(L10n.bestValue)" : ""
        let button = NSButton(
            title: "\(title)\(badge)\n\(subtitle) - \(product.displayPrice)",
            target: self,
            action: #selector(selectProduct(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(product.id)
        button.setButtonType(.radio)
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: product.id == ProProduct.lifetime.rawValue ? .semibold : .regular)
        button.state = product.id == selectedProductID ? .on : .off
        return button
    }

    @objc private func selectProduct(_ sender: NSButton) {
        guard let productID = sender.identifier?.rawValue else { return }
        selectedProductID = productID
        for view in productStack.arrangedSubviews {
            guard let button = view as? NSButton else { continue }
            button.state = button.identifier?.rawValue == productID ? .on : .off
        }
    }

    @objc private func purchaseSelectedProduct(_ sender: Any?) {
        purchaseButton.isEnabled = false
        statusLabel.stringValue = L10n.proPurchasing

        Task { [weak self] in
            guard let self else { return }
            do {
                try await entitlementService.purchase(productID: selectedProductID, confirmIn: self.window)
                statusLabel.stringValue = entitlementService.isProUnlocked ? L10n.proPurchaseComplete : L10n.proPurchaseCancelled
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
            purchaseButton.isEnabled = !entitlementService.isProUnlocked
            renderProducts()
        }
    }

    @objc private func restorePurchases(_ sender: Any?) {
        restoreButton.isEnabled = false
        statusLabel.stringValue = L10n.restoringPurchases

        Task { [weak self] in
            guard let self else { return }
            do {
                try await entitlementService.restorePurchases()
                statusLabel.stringValue = entitlementService.isProUnlocked ? L10n.proRestoreComplete : L10n.proRestoreEmpty
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
            restoreButton.isEnabled = true
            renderProducts()
        }
    }

    @objc private func manageSubscription(_ sender: Any?) {
        entitlementService.manageSubscriptions()
    }
}
