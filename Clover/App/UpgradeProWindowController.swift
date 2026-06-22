import AppKit
import StoreKit

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
                launchingPurchaseTitle: L10n.proLaunchingPurchase,
                legalLinks: Self.legalLinks
            ),
            productsProvider: { [entitlementService] in
                await entitlementService.loadProducts()
                return entitlementService.products.map { product in
                    let knownProduct = ProProduct(rawValue: product.id)
                    return MacPaywallProduct(
                        productID: product.id,
                        title: knownProduct?.displayTitle ?? product.displayName,
                        subtitle: knownProduct?.displaySubtitle ?? product.description,
                        originalPrice: Self.originalDisplayPrice(for: product, knownProduct: knownProduct),
                        currentPrice: product.displayPrice,
                        badge: knownProduct?.badgeTitle
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

    private static func originalDisplayPrice(for product: Product, knownProduct: ProProduct?) -> String? {
        guard let knownProduct else { return nil }
        let originalPrice = (product.price as NSDecimalNumber)
            .multiplying(by: knownProduct.originalPriceMultiplier as NSDecimalNumber)
            .decimalValue
        return product.priceFormatStyle.format(originalPrice)
    }

    private static var legalLinks: [MacPaywallLegalLink] {
        [
            MacPaywallLegalLink(
                title: L10n.privacyPolicy,
                url: URL(string: "https://yingxiang.github.io/clover/privacy.html")!
            ),
            MacPaywallLegalLink(
                title: L10n.termsOfUse,
                url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
            )
        ]
    }
}
