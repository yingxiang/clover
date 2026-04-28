import Foundation

struct PaneState: Codable, Identifiable {
    var id: UUID
    var currentURLBookmark: Data?
    var currentPath: String
    var viewMode: FileViewMode
    var sortOption: SortOption
    var selectedFileNames: [String]
    var backHistory: [String]
    var forwardHistory: [String]

    static func home(id: UUID = UUID()) -> PaneState {
        PaneState(id: id, currentURLBookmark: nil, currentPath: FileManager.default.homeDirectoryForCurrentUser.path, viewMode: .list, sortOption: .nameAscending, selectedFileNames: [], backHistory: [], forwardHistory: [])
    }
}

enum PaneLayout: String, Codable, CaseIterable {
    case single
    case twoVertical
    case twoHorizontal
    case fourGrid
}
