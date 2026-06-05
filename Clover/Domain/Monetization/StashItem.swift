import Foundation

struct StashItem: Codable, Identifiable, Hashable {
    var id: UUID
    var displayName: String
    var path: String
    var bookmarkData: Data?
    var createdAt: Date

    var url: URL? {
        if let bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return resolvedURL
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
    }

    init(id: UUID = UUID(), url: URL, bookmarkStore: BookmarkStore? = nil, createdAt: Date = Date()) {
        self.id = id
        self.displayName = url.lastPathComponent
        self.path = url.path
        self.bookmarkData = try? bookmarkStore?.bookmarkData(for: url)
        self.createdAt = createdAt
    }
}
