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
            return String(localized: "pro_lifetime", defaultValue: "Lifetime Pro")
        case .threeMonths:
            return String(localized: "pro_three_months", defaultValue: "3 Months Pro")
        case .sixMonths:
            return String(localized: "pro_six_months", defaultValue: "6 Months Pro")
        case .yearly:
            return String(localized: "pro_yearly", defaultValue: "Yearly Pro")
        }
    }

    var displaySubtitle: String {
        switch self {
        case .lifetime:
            return String(localized: "pro_lifetime_subtitle", defaultValue: "One purchase, permanent access")
        case .threeMonths:
            return String(localized: "pro_three_months_subtitle", defaultValue: "Short-term access")
        case .sixMonths:
            return String(localized: "pro_six_months_subtitle", defaultValue: "For focused projects")
        case .yearly:
            return String(localized: "pro_yearly_subtitle", defaultValue: "Best subscription value")
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
            return String(localized: "best_value", defaultValue: "Best Value")
        case .yearly:
            return String(localized: "good_value", defaultValue: "Good Value")
        case .sixMonths, .threeMonths:
            return String(localized: "limited_offer", defaultValue: "Limited Offer")
        }
    }
}
