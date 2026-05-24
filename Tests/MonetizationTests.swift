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

    func testOnlyNewProFeaturesAreRegistered() {
        XCTAssertEqual(Set(ProFeature.allCases), [
            .namedWorkspaces,
            .stashShelf,
            .batchRename,
            .folderCompare,
            .customToolbar,
            .advancedShortcuts
        ])
    }
}
