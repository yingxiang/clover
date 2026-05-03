import Foundation

final class DirectoryAccessStore {
    private let fileManager: FileManager
    private let storageURL: URL
    private let bookmarkStore: BookmarkStore
    private var cachedBookmarks: [String: Data]?

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        bookmarkStore: BookmarkStore = BookmarkStore()
    ) throws {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let supportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.storageURL = supportURL
                .appendingPathComponent("Clover", isDirectory: true)
                .appendingPathComponent("Security", isDirectory: true)
                .appendingPathComponent("DirectoryBookmarks.plist", isDirectory: false)
        }
    }

    func resolvedURL(for url: URL) -> URL? {
        let standardizedURL = url.standardizedFileURL
        guard let data = bookmarks()[standardizedURL.path] else { return nil }
        do {
            return try bookmarkStore.resolveBookmark(data)
        } catch {
            removeBookmark(for: standardizedURL)
            return nil
        }
    }

    func saveAccess(to url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        var storedBookmarks = bookmarks()
        storedBookmarks[standardizedURL.path] = try bookmarkStore.bookmarkData(for: standardizedURL)
        try persistBookmarks(storedBookmarks)
    }

    private func bookmarks() -> [String: Data] {
        if let cachedBookmarks {
            return cachedBookmarks
        }

        guard fileManager.fileExists(atPath: storageURL.path) else {
            cachedBookmarks = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try PropertyListDecoder().decode([String: Data].self, from: data)
            cachedBookmarks = decoded
            return decoded
        } catch {
            cachedBookmarks = [:]
            return [:]
        }
    }

    private func persistBookmarks(_ bookmarks: [String: Data]) throws {
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListEncoder().encode(bookmarks)
        try data.write(to: storageURL, options: .atomic)
        cachedBookmarks = bookmarks
    }

    private func removeBookmark(for url: URL) {
        var storedBookmarks = bookmarks()
        storedBookmarks.removeValue(forKey: url.standardizedFileURL.path)
        try? persistBookmarks(storedBookmarks)
    }
}
