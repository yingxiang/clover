import Foundation

enum FileSortService {
    static func sort(_ items: [FileItem], by option: SortOption) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            switch option {
            case .nameAscending:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .dateAscending:
                return (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
            case .dateDescending:
                return (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
            case .sizeAscending:
                return (lhs.size ?? -1) < (rhs.size ?? -1)
            case .sizeDescending:
                return (lhs.size ?? -1) > (rhs.size ?? -1)
            case .typeAscending:
                return (lhs.typeIdentifier ?? "").localizedStandardCompare(rhs.typeIdentifier ?? "") == .orderedAscending
            case .typeDescending:
                return (lhs.typeIdentifier ?? "").localizedStandardCompare(rhs.typeIdentifier ?? "") == .orderedDescending
            }
        }
    }
}
