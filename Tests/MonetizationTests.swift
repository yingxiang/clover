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
        XCTAssertEqual(ProProduct.lifetime.badgeTitle, String(localized: "best_value", defaultValue: "Best Value"))
        XCTAssertEqual(ProProduct.yearly.badgeTitle, String(localized: "good_value", defaultValue: "Good Value"))
        XCTAssertEqual(ProProduct.sixMonths.badgeTitle, String(localized: "limited_offer", defaultValue: "Limited Offer"))
        XCTAssertEqual(ProProduct.threeMonths.badgeTitle, String(localized: "limited_offer", defaultValue: "Limited Offer"))
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
