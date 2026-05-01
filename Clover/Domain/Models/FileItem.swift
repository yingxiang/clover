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
    static func typeKey(for item: FileItem) -> String {
        if item.isApplication {
            return "application"
        }
        if item.isBrowsableDirectory {
            return "folder"
        }
        if let identifier = item.typeIdentifier,
           let type = UTType(identifier) {
            return "uti:\(type.identifier)"
        }
        if item.url.pathExtension.isEmpty {
            return "file"
        }
        return "ext:\(item.url.pathExtension.lowercased())"
    }

    static func typeName(for item: FileItem) -> String {
        localizedTypeName(for: typeKey(for: item), fallbackName: fallbackTypeName(for: item))
    }

    static func localizedTypeName(for key: String, fallbackName: String? = nil) -> String {
        switch key {
        case "application":
            return L10n.typeApplication
        case "folder":
            return L10n.typeFolder
        case "file":
            return L10n.typeFile
        default:
            if let fallbackName, !fallbackName.isEmpty {
                return fallbackName
            }
            if let identifier = key.split(separator: ":", maxSplits: 1).last,
               key.hasPrefix("uti:"),
               let type = UTType(String(identifier)) {
                return type.localizedDescription ?? String(identifier)
            }
            if let ext = key.split(separator: ":", maxSplits: 1).last,
               key.hasPrefix("ext:") {
                return ext.uppercased()
            }
            return key
        }
    }

    private static func fallbackTypeName(for item: FileItem) -> String {
        if item.isApplication {
            return L10n.typeApplication
        }
        if item.isBrowsableDirectory {
            return L10n.typeFolder
        }
        if let identifier = item.typeIdentifier,
           let type = UTType(identifier) {
            return type.localizedDescription ?? identifier
        }
        return item.url.pathExtension.isEmpty ? L10n.typeFile : item.url.pathExtension.uppercased()
    }
}
