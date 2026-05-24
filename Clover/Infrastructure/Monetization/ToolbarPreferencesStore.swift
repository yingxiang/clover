import Foundation

final class ToolbarPreferencesStore {
    enum Item: String, CaseIterable {
        case refresh
        case terminal
        case airDrop
        case share
        case info
        case viewMode
        case paneLayout
    }

    private let defaults: UserDefaults
    private let key = "Clover.ToolbarPreferences.visibleItems"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var visibleItems: Set<Item> {
        get {
            if let stored = defaults.array(forKey: key) as? [String] {
                return Set(stored.compactMap(Item.init(rawValue:)))
            }
            return Set(Item.allCases)
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: key)
        }
    }

    func isVisible(_ item: Item) -> Bool {
        visibleItems.contains(item)
    }

    func setVisible(_ item: Item, visible: Bool) {
        var items = visibleItems
        if visible {
            items.insert(item)
        } else {
            items.remove(item)
        }
        visibleItems = items
    }
}
