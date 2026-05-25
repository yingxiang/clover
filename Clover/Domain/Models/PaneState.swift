import Foundation
import Darwin

enum UserDirectories {
    static var homeURL: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            let homePath = String(cString: home)
            if !homePath.isEmpty {
                return URL(fileURLWithPath: homePath, isDirectory: true).standardizedFileURL
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }
}

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
        PaneState(id: id, currentURLBookmark: nil, currentPath: UserDirectories.homeURL.path, viewMode: .list, sortOption: .nameAscending, selectedFileNames: [], backHistory: [], forwardHistory: [])
    }
}

enum PaneLayout: String, Codable, CaseIterable {
    case single
    case twoVertical
    case twoHorizontal
    case leftOneRightTwo
    case leftTwoRightOne
    case topOneBottomTwo
    case topTwoBottomOne
    case fourGrid
}
