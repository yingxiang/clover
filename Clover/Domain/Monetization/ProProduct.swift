import Foundation

enum ProProduct: String, CaseIterable, Sendable {
    case lifetime = "unlock_all"
    case threeMonths = "clover_buy_three_month"
    case sixMonths = "clover_buy_six_month"
    case yearly = "clover_buy_one_year"

    static let orderedProductIDs = [
        ProProduct.lifetime.rawValue,
        ProProduct.yearly.rawValue,
        ProProduct.sixMonths.rawValue,
        ProProduct.threeMonths.rawValue
    ]

    var displayTitle: String {
        switch self {
        case .lifetime:
            return L10n.proLifetime
        case .threeMonths:
            return L10n.proThreeMonths
        case .sixMonths:
            return L10n.proSixMonths
        case .yearly:
            return L10n.proYearly
        }
    }

    var displaySubtitle: String {
        switch self {
        case .lifetime:
            return L10n.proLifetimeSubtitle
        case .threeMonths:
            return L10n.proThreeMonthsSubtitle
        case .sixMonths:
            return L10n.proSixMonthsSubtitle
        case .yearly:
            return L10n.proYearlySubtitle
        }
    }

    var originalPriceMultiplier: Decimal {
        switch self {
        case .lifetime, .sixMonths, .yearly:
            return 2
        case .threeMonths:
            return 3
        }
    }

    var badgeTitle: String {
        switch self {
        case .lifetime:
            return L10n.bestValue
        case .yearly:
            return L10n.goodValue
        case .sixMonths, .threeMonths:
            return L10n.limitedOffer
        }
    }
}
