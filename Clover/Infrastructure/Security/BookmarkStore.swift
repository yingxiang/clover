import Foundation

final class BookmarkStore {
    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        return try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
}
