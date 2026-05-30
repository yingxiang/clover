import AppKit

@MainActor
final class UpgradeProWindowController: NSWindowController {
    private let entitlementService: EntitlementService
    private var presenter: MacPaywallPresenter?

    init(entitlementService: EntitlementService) {
        self.entitlementService = entitlementService
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        let presenter = MacPaywallPresenter(
            configuration: MacPaywallConfiguration(
                title: L10n.upgradeToPro,
                unlockedTitle: L10n.proPurchaseComplete,
                failureTitle: L10n.proPurchaseFailed,
                emptyProductsMessage: L10n.proNoProducts,
                benefits: ProFeature.visibleFeatures.map(\.title),
                laterTitle: L10n.cancel,
                okTitle: L10n.ok,
                launchingPurchaseTitle: L10n.proLaunchingPurchase
            ),
            productsProvider: { [entitlementService] in
                await entitlementService.loadProducts()
                return entitlementService.products.map { product in
                    let knownProduct = ProProduct(rawValue: product.id)
                    return MacPaywallProduct(
                        productID: product.id,
                        title: knownProduct?.displayTitle ?? product.displayName,
                        subtitle: knownProduct?.displaySubtitle ?? product.description,
                        originalPrice: nil,
                        currentPrice: product.displayPrice,
                        badge: product.id == ProProduct.lifetime.rawValue ? L10n.bestValue : nil
                    )
                }
            },
            isUnlocked: { [entitlementService] in
                entitlementService.isProUnlocked
            },
            purchaseHandler: { [entitlementService] productID, window in
                try await entitlementService.purchase(productID: productID, confirmIn: window)
                return entitlementService.isProUnlocked
            }
        )
        self.presenter = presenter
        presenter.show()
    }
}
