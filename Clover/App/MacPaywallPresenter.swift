import AppKit

struct MacPaywallProduct {
    let productID: String
    let title: String
    let subtitle: String?
    let originalPrice: String?
    let currentPrice: String
    let badge: String?

    init(
        productID: String,
        title: String,
        subtitle: String? = nil,
        originalPrice: String? = nil,
        currentPrice: String,
        badge: String? = nil
    ) {
        self.productID = productID
        self.title = title
        self.subtitle = subtitle
        self.originalPrice = originalPrice
        self.currentPrice = currentPrice
        self.badge = badge
    }
}

struct MacPaywallLegalLink {
    let title: String
    let url: URL
}

struct MacPaywallConfiguration {
    let title: String
    let unlockedTitle: String
    let legacyUnlockedTitle: String?
    let failureTitle: String
    let emptyProductsMessage: String
    let benefits: [String]
    let laterTitle: String
    let okTitle: String
    let launchingPurchaseTitle: String
    let legalLinks: [MacPaywallLegalLink]

    init(
        title: String,
        unlockedTitle: String,
        legacyUnlockedTitle: String? = nil,
        failureTitle: String,
        emptyProductsMessage: String,
        benefits: [String],
        laterTitle: String,
        okTitle: String,
        launchingPurchaseTitle: String,
        legalLinks: [MacPaywallLegalLink] = []
    ) {
        self.title = title
        self.unlockedTitle = unlockedTitle
        self.legacyUnlockedTitle = legacyUnlockedTitle
        self.failureTitle = failureTitle
        self.emptyProductsMessage = emptyProductsMessage
        self.benefits = benefits
        self.laterTitle = laterTitle
        self.okTitle = okTitle
        self.launchingPurchaseTitle = launchingPurchaseTitle
        self.legalLinks = legalLinks
    }
}

private struct MacPaywallButtonContent {
    let title: String
    let subtitle: String?
    let originalPrice: String?
    let currentPrice: String?
    let badge: String?
    let response: NSApplication.ModalResponse
    let isPurchaseOption: Bool

    static func button(_ title: String, response: NSApplication.ModalResponse) -> Self {
        Self(title: title, subtitle: nil, originalPrice: nil, currentPrice: nil, badge: nil, response: response, isPurchaseOption: false)
    }

    static func product(_ product: MacPaywallProduct, response: NSApplication.ModalResponse) -> Self {
        Self(
            title: product.title,
            subtitle: product.subtitle,
            originalPrice: product.originalPrice,
            currentPrice: product.currentPrice,
            badge: product.badge,
            response: response,
            isPurchaseOption: true
        )
    }
}

private let macPaywallCancelResponse = NSApplication.ModalResponse(rawValue: 0)

@MainActor
final class MacPaywallPresenter {
    typealias ProductsProvider = () async -> [MacPaywallProduct]
    typealias UnlockedProvider = () -> Bool
    typealias LegacyUnlockedProvider = () -> Bool
    typealias PurchaseHandler = (_ productID: String, _ hostWindow: NSWindow?) async throws -> Bool

    private let configuration: MacPaywallConfiguration
    private let productsProvider: ProductsProvider
    private let isUnlocked: UnlockedProvider
    private let isLegacyUnlocked: LegacyUnlockedProvider
    private let purchaseHandler: PurchaseHandler
    private var products: [MacPaywallProduct] = []
    private var isPresenting = false
    private var purchaseHostPanel: MacPaywallWindow?
    private weak var hiddenSourceWindow: NSWindow?

    init(
        configuration: MacPaywallConfiguration,
        productsProvider: @escaping ProductsProvider,
        isUnlocked: @escaping UnlockedProvider,
        isLegacyUnlocked: @escaping LegacyUnlockedProvider = { false },
        purchaseHandler: @escaping PurchaseHandler
    ) {
        self.configuration = configuration
        self.productsProvider = productsProvider
        self.isUnlocked = isUnlocked
        self.isLegacyUnlocked = isLegacyUnlocked
        self.purchaseHandler = purchaseHandler
    }

    func show(sourceWindowToHide: NSWindow? = nil) {
        guard !isPresenting else { return }
        isPresenting = true

        Task {
            products = await productsProvider()
            present(sourceWindowToHide: sourceWindowToHide)
        }
    }

    private func present(sourceWindowToHide: NSWindow?) {
        if isUnlocked() {
            _ = runPaywall(
                title: isLegacyUnlocked() ? (configuration.legacyUnlockedTitle ?? configuration.unlockedTitle) : configuration.unlockedTitle,
                message: benefitsText(),
                buttons: [.button(configuration.okTitle, response: .alertFirstButtonReturn)],
                sourceWindowToHide: sourceWindowToHide
            )
            isPresenting = false
            return
        }

        guard !products.isEmpty else {
            _ = runPaywall(
                title: configuration.title,
                message: configuration.emptyProductsMessage,
                buttons: [.button(configuration.okTitle, response: .alertFirstButtonReturn)],
                sourceWindowToHide: sourceWindowToHide
            )
            isPresenting = false
            return
        }

        let response = runPaywall(
            title: configuration.title,
            message: benefitsText(),
            buttons: productButtons(),
            sourceWindowToHide: sourceWindowToHide
        )
        isPresenting = false

        guard let productID = productID(for: response) else { return }
        Task { await purchase(productID: productID, sourceWindowToHide: sourceWindowToHide) }
    }

    private func purchase(productID: String, sourceWindowToHide: NSWindow?) async {
        let originalActivationPolicy = NSApp.activationPolicy()
        let purchaseHostWindow = purchaseHostPanel
        let hostWindow = purchaseHostWindow ?? sourceWindowToHide
        let originalLevel = hostWindow?.level
        let wasVisible = hostWindow?.isVisible ?? false

        if originalActivationPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if let hostWindow {
            hostWindow.level = .normal
            hostWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        var result: (title: String, message: String)?
        do {
            let unlocked = try await purchaseHandler(productID, hostWindow)
            if unlocked {
                result = (configuration.unlockedTitle, benefitsText())
            }
        } catch {
            result = (configuration.failureTitle, error.localizedDescription)
        }

        if let hostWindow, hostWindow !== purchaseHostWindow, let originalLevel {
            hostWindow.level = originalLevel
            if wasVisible {
                hostWindow.makeKeyAndOrderFront(nil)
            }
        }

        if let result {
            showResultInPurchaseHostPanel(title: result.title, message: result.message)
        } else {
            resumePurchaseHostPanel(sourceWindowToHide: sourceWindowToHide)
        }

        if originalActivationPolicy != .regular {
            NSApp.setActivationPolicy(originalActivationPolicy)
        }
    }

    private func runPaywall(
        title: String,
        message: String,
        buttons: [MacPaywallButtonContent],
        sourceWindowToHide: NSWindow?
    ) -> NSApplication.ModalResponse {
        let page = MacPurchasePaywallView(
            title: title,
            message: message,
            buttons: buttons,
            launchingPurchaseTitle: configuration.launchingPurchaseTitle,
            legalLinks: configuration.legalLinks
        )
        let size = page.preferredContentSize()
        let panel = MacPaywallWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = page
        page.frame = NSRect(origin: .zero, size: size)
        page.autoresizingMask = [.width, .height]
        page.onResponse = { [weak panel] response in
            panel?.closeWithResponse(response)
        }

        hiddenSourceWindow = sourceWindowToHide
        sourceWindowToHide?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)

        if productID(for: response) != nil {
            purchaseHostPanel = panel
        } else {
            panel.orderOut(nil)
            restoreHiddenSourceWindow()
        }
        return response
    }

    private func showResultInPurchaseHostPanel(title: String, message: String) {
        guard let panel = purchaseHostPanel,
              let page = panel.contentView as? MacPurchasePaywallView else {
            _ = runPaywall(
                title: title,
                message: message,
                buttons: [.button(configuration.okTitle, response: .alertFirstButtonReturn)],
                sourceWindowToHide: nil
            )
            return
        }

        page.updateContent(title: title, message: message, buttons: [.button(configuration.okTitle, response: .alertFirstButtonReturn)])
        let paywallSize = page.preferredContentSize()
        panel.setContentSize(paywallSize)
        page.frame = NSRect(origin: .zero, size: paywallSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        _ = NSApp.runModal(for: panel)
        closePurchaseHostPanel()
    }

    private func resumePurchaseHostPanel(sourceWindowToHide: NSWindow?) {
        guard let panel = purchaseHostPanel else { return }
        restorePurchaseHostPanelOptions(panel)
        panel.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: panel)
        guard let productID = productID(for: response) else {
            closePurchaseHostPanel()
            return
        }
        Task { await purchase(productID: productID, sourceWindowToHide: sourceWindowToHide) }
    }

    private func restorePurchaseHostPanelOptions(_ panel: MacPaywallWindow) {
        guard let page = panel.contentView as? MacPurchasePaywallView else { return }
        page.updateContent(title: configuration.title, message: benefitsText(), buttons: productButtons())
        let paywallSize = page.preferredContentSize()
        panel.setContentSize(paywallSize)
        page.frame = NSRect(origin: .zero, size: paywallSize)
        panel.center()
    }

    private func closePurchaseHostPanel() {
        purchaseHostPanel?.orderOut(nil)
        purchaseHostPanel = nil
        restoreHiddenSourceWindow()
    }

    private func restoreHiddenSourceWindow() {
        hiddenSourceWindow?.makeKeyAndOrderFront(nil)
        hiddenSourceWindow = nil
    }

    private func benefitsText() -> String {
        configuration.benefits.map { "• \($0)" }.joined(separator: "\n")
    }

    private func productButtons() -> [MacPaywallButtonContent] {
        var buttons = products.enumerated().map { index, product in
            MacPaywallButtonContent.product(product, response: NSApplication.ModalResponse(rawValue: 1000 + index))
        }
        buttons.append(.button(configuration.laterTitle, response: macPaywallCancelResponse))
        return buttons
    }

    private func productID(for response: NSApplication.ModalResponse) -> String? {
        let index = response.rawValue - 1000
        guard products.indices.contains(index) else { return nil }
        return products[index].productID
    }
}

private final class MacPaywallWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            closeWithResponse(macPaywallCancelResponse)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        closeWithResponse(macPaywallCancelResponse)
    }

    func closeWithResponse(_ response: NSApplication.ModalResponse) {
        NSApp.stopModal(withCode: response)
    }
}

private class MacPaywallBlurView: NSView {
    private lazy var effectView: NSView = {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        let view = visualEffectView
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: nil)
        let minimumHeight = view.heightAnchor.constraint(greaterThanOrEqualToConstant: 65)
        let matchingHeight = view.heightAnchor.constraint(equalTo: heightAnchor)
        matchingHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            minimumHeight,
            matchingHeight
        ])
        return view
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.masksToBounds = true
        _ = effectView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class MacPurchasePaywallView: MacPaywallBlurView {
    static let preferredWidth: CGFloat = 488

    var onResponse: ((NSApplication.ModalResponse) -> Void)?
    private var buttons: [NSButton] = []
    private let launchingPurchaseTitle: String
    private let legalLinks: [MacPaywallLegalLink]
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let buttonRow = NSStackView()
    private let buttonSpacer = NSView()

    init(
        title: String,
        message: String,
        buttons: [MacPaywallButtonContent],
        launchingPurchaseTitle: String,
        legalLinks: [MacPaywallLegalLink]
    ) {
        self.launchingPurchaseTitle = launchingPurchaseTitle
        self.legalLinks = legalLinks
        super.init(frame: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 1))
        setupContent(title: title, message: message, buttons: buttons)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -6)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    func preferredContentSize(width: CGFloat = MacPurchasePaywallView.preferredWidth) -> CGSize {
        let widthConstraint = widthAnchor.constraint(equalToConstant: width)
        widthConstraint.isActive = true
        layoutSubtreeIfNeeded()
        let height = ceil(fittingSize.height)
        widthConstraint.isActive = false
        return CGSize(width: width, height: max(65, height))
    }

    func updateContent(title: String, message: String, buttons buttonContents: [MacPaywallButtonContent]) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        let usesVerticalButtons = buttonContents.count > 2
        buttonRow.orientation = usesVerticalButtons ? .vertical : .horizontal
        buttonRow.alignment = usesVerticalButtons ? .centerX : .centerY
        buttonRow.spacing = usesVerticalButtons ? 8 : 10
        buttonSpacer.isHidden = usesVerticalButtons

        for button in buttons {
            buttonRow.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        buttons.removeAll()

        for (index, content) in buttonContents.enumerated() {
            let button: NSButton
            if content.isPurchaseOption {
                button = MacPurchaseOptionButton(content: content, target: self, action: #selector(buttonClicked(_:)))
            } else {
                button = NSButton(title: content.title, target: self, action: #selector(buttonClicked(_:)))
                button.bezelStyle = .rounded
            }
            button.tag = content.response.rawValue
            button.keyEquivalent = index == 0 ? "\r" : ""
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
            if content.isPurchaseOption {
                button.widthAnchor.constraint(equalToConstant: 390).isActive = true
                button.heightAnchor.constraint(equalToConstant: 58).isActive = true
            }
            buttonRow.addArrangedSubview(button)
            buttons.append(button)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func setupContent(title: String, message: String, buttons: [MacPaywallButtonContent]) {
        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 16
        addSubview(root)

        let bodyRow = NSStackView()
        bodyRow.translatesAutoresizingMaskIntoConstraints = false
        bodyRow.orientation = .horizontal
        bodyRow.alignment = .top
        bodyRow.spacing = 16

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.isSelectable = false
        messageLabel.stringValue = message
        messageLabel.font = NSFont.systemFont(ofSize: 13)
        messageLabel.textColor = .labelColor
        messageLabel.isSelectable = false

        let textStack = NSStackView(views: [titleLabel, messageLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        bodyRow.addArrangedSubview(iconView)
        bodyRow.addArrangedSubview(textStack)

        buttonSpacer.translatesAutoresizingMaskIntoConstraints = false
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(buttonSpacer)
        updateContent(title: title, message: message, buttons: buttons)

        root.addArrangedSubview(bodyRow)
        root.addArrangedSubview(buttonRow)
        if !legalLinks.isEmpty {
            root.addArrangedSubview(makeLegalLinksView())
        }
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            textStack.widthAnchor.constraint(equalToConstant: 320),
            textStack.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -80),
            bodyRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            messageLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor)
        ])
    }

    private func makeLegalLinksView() -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        for (index, link) in legalLinks.enumerated() {
            if index > 0 {
                let separator = NSTextField(labelWithString: "•")
                separator.font = .systemFont(ofSize: 11)
                separator.textColor = .secondaryLabelColor
                stack.addArrangedSubview(separator)
            }

            let button = NSButton(title: link.title, target: self, action: #selector(legalLinkClicked(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .linkColor
            button.setAccessibilityLabel(link.title)
            stack.addArrangedSubview(button)
        }

        return stack
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        if let purchaseButton = sender as? MacPurchaseOptionButton {
            showPurchaseLaunchingState(selectedButton: purchaseButton)
        }
        onResponse?(NSApplication.ModalResponse(rawValue: sender.tag))
    }

    private func showPurchaseLaunchingState(selectedButton: MacPurchaseOptionButton) {
        for button in buttons {
            button.isEnabled = false
            button.keyEquivalent = ""
        }
        selectedButton.showLoading(title: launchingPurchaseTitle)
    }

    @objc private func legalLinkClicked(_ sender: NSButton) {
        guard legalLinks.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(legalLinks[sender.tag].url)
    }
}

private final class MacPurchaseOptionButton: NSButton {
    private let cornerRadius: CGFloat = 8
    private let progressIndicator = NSProgressIndicator()
    private let content: MacPaywallButtonContent
    private var loadingTitle: String?
    private var isShowingLoading = false

    init(content: MacPaywallButtonContent, target: AnyObject?, action: Selector?) {
        self.content = content
        super.init(frame: .zero)
        self.title = content.title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        focusRingType = .none
        setAccessibilityLabel(content.title)
        configureProgressIndicator()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 384, height: 58)
    }

    func showLoading(title: String) {
        isShowingLoading = true
        loadingTitle = title
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isPrimary = keyEquivalent == "\r"
        let backgroundColor: NSColor
        if isPrimary {
            backgroundColor = isHighlighted ? NSColor.controlAccentColor.withSystemEffect(.pressed) : NSColor.controlAccentColor
        } else {
            backgroundColor = isHighlighted
                ? NSColor.controlBackgroundColor.withAlphaComponent(0.58)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.42)
        }
        backgroundColor.setFill()
        let borderBounds = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: borderBounds, xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()
        let strokeColor = isPrimary
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor.separatorColor.withAlphaComponent(0.55)
        strokeColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let contentRect = bounds.insetBy(dx: 12, dy: 6)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: contentRect).addClip()
        let title = fittedTitle(maxWidth: contentRect.width, isPrimary: isPrimary)
        let titleSize = title.size()
        let titleRect = NSRect(
            x: floor((bounds.width - min(titleSize.width, contentRect.width)) / 2),
            y: floor((bounds.height - titleSize.height) / 2),
            width: min(titleSize.width, contentRect.width),
            height: titleSize.height
        )
        title.draw(in: titleRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func configureProgressIndicator() {
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        addSubview(progressIndicator)
        NSLayoutConstraint.activate([
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func attributedTitle(for content: MacPaywallButtonContent, isPrimary: Bool) -> NSAttributedString {
        let text = [content.title, content.originalPrice, content.currentPrice, content.badge].compactMap(\.self).joined(separator: " ")
        let titleColor = isPrimary
            ? NSColor.white
            : NSColor.labelColor
        let secondaryColor = isPrimary
            ? NSColor.white.withAlphaComponent(0.72)
            : NSColor.secondaryLabelColor
        let priceColor = isPrimary
            ? NSColor.white
            : NSColor.labelColor
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: titleColor
            ]
        )
        let nsText = text as NSString
        if let originalPrice = content.originalPrice {
            attributed.addAttributes(
                [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: secondaryColor
                ],
                range: nsText.range(of: originalPrice)
            )
        }
        if let currentPrice = content.currentPrice {
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 26, weight: .bold),
                    .foregroundColor: priceColor
                ],
                range: nsText.range(of: currentPrice)
            )
        }
        if let badge = content.badge {
            attributed.addAttributes(
                [.foregroundColor: NSColor.systemGreen],
                range: nsText.range(of: badge, options: .backwards)
            )
        }
        return attributed
    }

    private func fittedTitle(maxWidth availableWidth: CGFloat, isPrimary: Bool) -> NSAttributedString {
        let source = isShowingLoading
            ? loadingAttributedTitle(isPrimary: isPrimary)
            : attributedTitle(for: content, isPrimary: isPrimary)
        let currentWidth = max(1, source.size().width)
        let fitted = NSMutableAttributedString(attributedString: source)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        fitted.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: fitted.length))
        guard currentWidth > availableWidth else { return fitted }
        let scale = availableWidth / currentWidth
        fitted.enumerateAttribute(.font, in: NSRange(location: 0, length: fitted.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let scaledFont = NSFontManager.shared.convert(font, toSize: max(8, font.pointSize * scale))
            fitted.addAttribute(.font, value: scaledFont, range: range)
        }
        return fitted
    }

    private func loadingAttributedTitle(isPrimary: Bool) -> NSAttributedString {
        NSAttributedString(
            string: loadingTitle ?? title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: isPrimary ? NSColor.white : NSColor.labelColor
            ]
        )
    }
}
