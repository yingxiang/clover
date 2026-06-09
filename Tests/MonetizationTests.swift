import XCTest
@testable import Clover

final class MonetizationTests: XCTestCase {
    func testProProductsUsePlannedIdentifiersAndOrder() {
        XCTAssertEqual(ProProduct.lifetime.rawValue, "unlock_all")
        XCTAssertEqual(ProProduct.threeMonths.rawValue, "clover_buy_three_month")
        XCTAssertEqual(ProProduct.sixMonths.rawValue, "clover_buy_six_month")
        XCTAssertEqual(ProProduct.yearly.rawValue, "clover_buy_one_year")

        XCTAssertEqual(ProProduct.orderedProductIDs, [
            "unlock_all",
            "clover_buy_one_year",
            "clover_buy_six_month",
            "clover_buy_three_month"
        ])
    }

    func testProProductsUseMapleOriginalPriceMultipliers() {
        XCTAssertEqual(ProProduct.lifetime.originalPriceMultiplier, 2)
        XCTAssertEqual(ProProduct.yearly.originalPriceMultiplier, 2)
        XCTAssertEqual(ProProduct.sixMonths.originalPriceMultiplier, 2)
        XCTAssertEqual(ProProduct.threeMonths.originalPriceMultiplier, 3)
    }

    func testProProductsUseMapleBadgeTitles() {
        XCTAssertEqual(ProProduct.lifetime.badgeTitle, L10n.bestValue)
        XCTAssertEqual(ProProduct.yearly.badgeTitle, L10n.goodValue)
        XCTAssertEqual(ProProduct.sixMonths.badgeTitle, L10n.limitedOffer)
        XCTAssertEqual(ProProduct.threeMonths.badgeTitle, L10n.limitedOffer)
    }

    func testOnlyNewProFeaturesAreRegistered() {
        XCTAssertEqual(Set(ProFeature.allCases), [
            .namedWorkspaces,
            .stashShelf,
            .batchRename,
            .folderCompare,
            .customToolbar,
            .advancedPaneLayouts,
            .advancedShortcuts
        ])
    }
}
