import AppKit
import Combine
import Foundation
import StoreKit

@MainActor
final class EntitlementService: ObservableObject {
    enum PurchaseError: LocalizedError {
        case productUnavailable
        case pending
        case unverified

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return L10n.proProductUnavailable
            case .pending:
                return L10n.proPurchasePending
            case .unverified:
                return L10n.proPurchaseUnverified
            }
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productLoadError: Error?
    @Published private(set) var isProUnlocked = false
    @Published private(set) var activeProductIDs: Set<String> = []

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try checkVerified(result)
                    await refreshPurchasedProducts()
                    await transaction.finish()
                } catch {
                    productLoadError = error
                }
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        productLoadError = nil
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: ProProduct.orderedProductIDs)
            products = loadedProducts.sorted { first, second in
                orderIndex(for: first.id) < orderIndex(for: second.id)
            }
            await refreshPurchasedProducts()
        } catch {
            productLoadError = error
        }
    }

    func purchase(productID: String, confirmIn window: NSWindow? = nil) async throws {
        if products.isEmpty {
            await loadProducts()
        }

        guard let product = products.first(where: { $0.id == productID }) else {
            throw PurchaseError.productUnavailable
        }

        let result: Product.PurchaseResult
        if #available(macOS 15.2, *), let window {
            result = try await product.purchase(confirmIn: window)
        } else {
            result = try await product.purchase()
        }
        switch result {
        case .success(let verificationResult):
            let transaction = try checkVerified(verificationResult)
            await refreshPurchasedProducts()
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            throw PurchaseError.pending
        @unknown default:
            throw PurchaseError.unverified
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshPurchasedProducts()
    }

    func manageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshPurchasedProducts() async {
        var purchasedProductIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  ProProduct(rawValue: transaction.productID) != nil else {
                continue
            }
            purchasedProductIDs.insert(transaction.productID)
        }

        activeProductIDs = purchasedProductIDs
        isProUnlocked = !purchasedProductIDs.isEmpty
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.unverified
        case .verified(let safe):
            return safe
        }
    }

    private func orderIndex(for productID: String) -> Int {
        ProProduct.orderedProductIDs.firstIndex(of: productID) ?? Int.max
    }
}
