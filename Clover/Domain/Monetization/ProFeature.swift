import Foundation

enum ProFeature: String, CaseIterable, Sendable {
    case namedWorkspaces
    case stashShelf
    case batchRename
    case folderCompare
    case customToolbar
    case advancedPaneLayouts
    case advancedShortcuts

    static let visibleFeatures: [ProFeature] = [
        .stashShelf,
        .advancedPaneLayouts
    ]

    var title: String {
        switch self {
        case .namedWorkspaces:
            return String(localized: "pro_feature_named_workspaces", defaultValue: "Multiple named workspaces")
        case .stashShelf:
            return String(localized: "pro_feature_stash_shelf", defaultValue: "Stash shelf for cross-folder collecting")
        case .batchRename:
            return String(localized: "pro_feature_batch_rename", defaultValue: "Batch rename with preview")
        case .folderCompare:
            return String(localized: "pro_feature_folder_compare", defaultValue: "Folder comparison between panes")
        case .customToolbar:
            return String(localized: "pro_feature_custom_toolbar", defaultValue: "Customizable toolbar")
        case .advancedPaneLayouts:
            return String(localized: "pro_feature_advanced_pane_layouts", defaultValue: "Unlock all pane layouts")
        case .advancedShortcuts:
            return String(localized: "pro_feature_advanced_shortcuts", defaultValue: "Advanced shortcuts for Pro workflows")
        }
    }
}
