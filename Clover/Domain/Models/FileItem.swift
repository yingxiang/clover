import Foundation
import UniformTypeIdentifiers

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
    let isPackage: Bool
    let isApplication: Bool

    init(url: URL, name: String, isDirectory: Bool, size: Int64?, modificationDate: Date?, creationDate: Date?, typeIdentifier: String?, isHidden: Bool, isPackage: Bool = false, isApplication: Bool = false) {
        self.id = url
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.typeIdentifier = typeIdentifier
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.isApplication = isApplication
    }

    var isBrowsableDirectory: Bool {
        isDirectory && !isPackage && !isApplication
    }
}

enum FileViewMode: String, Codable {
    case list
    case grid
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

enum FileItemPresentation {
    static func typeName(for item: FileItem) -> String {
        if item.isApplication {
            return "Application"
        }
        if item.isBrowsableDirectory {
            return "Folder"
        }
        if let identifier = item.typeIdentifier,
           let type = UTType(identifier) {
            return type.localizedDescription ?? identifier
        }
        return item.url.pathExtension.isEmpty ? "File" : item.url.pathExtension.uppercased()
    }
}
