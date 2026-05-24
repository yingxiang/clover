import Foundation

enum ProFeature: String, CaseIterable, Sendable {
    case namedWorkspaces
    case stashShelf
    case batchRename
    case folderCompare
    case customToolbar
    case advancedShortcuts

    var title: String {
        switch self {
        case .namedWorkspaces:
            return L10n.proFeatureNamedWorkspaces
        case .stashShelf:
            return L10n.proFeatureStashShelf
        case .batchRename:
            return L10n.proFeatureBatchRename
        case .folderCompare:
            return L10n.proFeatureFolderCompare
        case .customToolbar:
            return L10n.proFeatureCustomToolbar
        case .advancedShortcuts:
            return L10n.proFeatureAdvancedShortcuts
        }
    }
}
