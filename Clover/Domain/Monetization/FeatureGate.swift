import Foundation

@MainActor
final class FeatureGate {
    private let entitlementService: EntitlementService

    init(entitlementService: EntitlementService) {
        self.entitlementService = entitlementService
    }

    func canUse(_ feature: ProFeature) -> Bool {
        entitlementService.isProUnlocked
    }
}
