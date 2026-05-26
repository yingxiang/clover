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
    private let contentWidth: CGFloat = 420

    init(entitlementService: EntitlementService) {
        self.entitlementService = entitlementService

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: L10n.upgradeToPro)
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1

        let subtitleLabel = NSTextField(labelWithString: L10n.proUpgradeSubtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let featureStack = NSStackView()
        featureStack.orientation = .vertical
        featureStack.alignment = .centerX
        featureStack.spacing = 8
        for feature in ProFeature.visibleFeatures {
            featureStack.addArrangedSubview(Self.makeFeatureRow(feature.title))
        }

        productStack.orientation = .vertical
        productStack.alignment = .width
        productStack.spacing = 10

        Self.configureActionButton(purchaseButton, width: contentWidth, emphasized: true)
        purchaseButton.keyEquivalent = "\r"
        Self.configureActionButton(restoreButton, width: contentWidth, emphasized: false)
        Self.configureActionButton(manageButton, width: contentWidth, emphasized: false)

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
        buttonStack.orientation = .vertical
        buttonStack.alignment = .centerX
        buttonStack.distribution = .fill
        buttonStack.spacing = 8

        let stackView = NSStackView(views: [titleLabel, subtitleLabel, featureStack, productStack, buttonStack, statusLabel])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 34),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),
            titleLabel.widthAnchor.constraint(equalToConstant: contentWidth),
            subtitleLabel.widthAnchor.constraint(equalToConstant: contentWidth),
            productStack.widthAnchor.constraint(equalToConstant: contentWidth),
            buttonStack.widthAnchor.constraint(equalToConstant: contentWidth),
            statusLabel.widthAnchor.constraint(equalToConstant: contentWidth)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.upgradeToPro
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
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

    private static func configureActionButton(_ button: NSButton, width: CGFloat, emphasized: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: emphasized ? .semibold : .regular)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
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
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2

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
        let badge = product.id == ProProduct.lifetime.rawValue ? L10n.bestValue : nil
        let button = ProProductOptionButton(
            productID: product.id,
            title: title,
            subtitle: subtitle,
            price: product.displayPrice,
            badge: badge,
            target: self,
            action: #selector(selectProduct(_:))
        )
        button.isSelected = product.id == selectedProductID
        button.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return button
    }

    @objc private func selectProduct(_ sender: ProProductOptionButton) {
        guard let productID = sender.identifier?.rawValue else { return }
        selectedProductID = productID
        for view in productStack.arrangedSubviews {
            guard let button = view as? ProProductOptionButton else { continue }
            button.isSelected = button.identifier?.rawValue == productID
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

private final class ProProductOptionButton: NSButton {
    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    init(productID: String, title: String, subtitle: String, price: String, badge: String?, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(productID)
        self.title = ""
        attributedTitle = NSAttributedString(string: "")
        alternateTitle = ""
        setButtonType(.momentaryChange)
        isBordered = false
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        focusRingType = .none
        setAccessibilityLabel(title)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping

        let priceLabel = NSTextField(labelWithString: price)
        priceLabel.font = .systemFont(ofSize: 15, weight: .bold)
        priceLabel.alignment = .center

        let contentViews: [NSView]
        if let badge {
            let badgeLabel = NSTextField(labelWithString: badge)
            badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
            badgeLabel.textColor = .controlAccentColor
            badgeLabel.alignment = .center
            badgeLabel.wantsLayer = true
            badgeLabel.layer?.cornerRadius = 8
            badgeLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            NSLayoutConstraint.activate([
                badgeLabel.heightAnchor.constraint(equalToConstant: 18),
                badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
            ])
            contentViews = [badgeLabel, titleLabel, subtitleLabel, priceLabel]
        } else {
            contentViews = [titleLabel, subtitleLabel, priceLabel]
        }

        let contentStack = NSStackView(views: contentViews)
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: badge == nil ? 78 : 96),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            priceLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        setPressedAppearance(true)
        super.mouseDown(with: event)
        setPressedAppearance(false)
    }

    private func setPressedAppearance(_ highlighted: Bool) {
        alphaValue = highlighted ? 0.85 : 1
    }

    private func updateAppearance() {
        layer?.cornerRadius = 12
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.controlBackgroundColor.withAlphaComponent(0.55)).cgColor
    }
}
