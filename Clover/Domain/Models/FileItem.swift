import Foundation

struct FileItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let typeIdentifier: String?
    let isHidden: Bool

    init(url: URL, name: String, isDirectory: Bool, size: Int64?, modificationDate: Date?, creationDate: Date?, typeIdentifier: String?, isHidden: Bool) {
        self.id = url
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.typeIdentifier = typeIdentifier
        self.isHidden = isHidden
    }
}

enum FileViewMode: String, Codable {
    case list
    case icon
}

enum SortOption: String, Codable {
    case nameAscending
    case nameDescending
    case dateAscending
    case dateDescending
    case sizeAscending
    case sizeDescending
    case typeAscending
    case typeDescending
}
