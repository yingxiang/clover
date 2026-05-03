import Foundation
import OSLog

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

        guard let match = bookmarkMatch(for: standardizedURL) else {
            return nil
        }
        do {
            let resolvedBookmarkURL = try bookmarkStore.resolveBookmark(match.data)
            return resolvedURL(for: standardizedURL, from: resolvedBookmarkURL, bookmarkPath: match.path)
        } catch {
            Logger.security.error("Directory access bookmark failed requested=\(standardizedURL.path, privacy: .public) granted=\(match.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            removeBookmark(forPath: match.path)
            return nil
        }
    }

    func saveAccess(to url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        var storedBookmarks = bookmarks()
        storedBookmarks[standardizedURL.path] = try bookmarkStore.bookmarkData(for: standardizedURL)
        try persistBookmarks(storedBookmarks)
        Logger.security.debug("Directory access saved path=\(standardizedURL.path, privacy: .public)")
    }

    func hasDirectoryAccess(to url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        if resolvedURL(for: standardizedURL) != nil {
            return true
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        do {
            _ = try fileManager.contentsOfDirectory(at: standardizedURL, includingPropertiesForKeys: nil, options: [])
            return true
        } catch {
            Logger.security.debug("Directory access check denied url=\(standardizedURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func securityScopeURL(for url: URL) -> URL? {
        let standardizedURL = url.standardizedFileURL
        guard let match = bookmarkMatch(for: standardizedURL) else {
            return nil
        }

        do {
            return try bookmarkStore.resolveBookmark(match.data).standardizedFileURL
        } catch {
            Logger.security.error("Directory access bookmark failed requested=\(standardizedURL.path, privacy: .public) granted=\(match.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            removeBookmark(forPath: match.path)
            return nil
        }
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
            Logger.security.error("Load directory bookmarks failed error=\(error.localizedDescription, privacy: .public)")
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
        removeBookmark(forPath: url.standardizedFileURL.path)
    }

    private func removeBookmark(forPath path: String) {
        var storedBookmarks = bookmarks()
        storedBookmarks.removeValue(forKey: path)
        try? persistBookmarks(storedBookmarks)
        Logger.security.debug("Directory access bookmark removed path=\(path, privacy: .public)")
    }

    private func bookmarkMatch(for url: URL) -> (path: String, data: Data)? {
        let urlPath = url.path
        return bookmarks()
            .filter { isPath(urlPath, equalToOrInside: $0.key) }
            .max { lhs, rhs in lhs.key.count < rhs.key.count }
            .map { (path: $0.key, data: $0.value) }
    }

    private func resolvedURL(for requestedURL: URL, from resolvedBookmarkURL: URL, bookmarkPath: String) -> URL {
        let bookmarkURL = URL(fileURLWithPath: bookmarkPath, isDirectory: true).standardizedFileURL
        let relativePath = requestedURL.pathComponents
            .dropFirst(bookmarkURL.pathComponents.count)
            .joined(separator: "/")

        guard !relativePath.isEmpty else {
            return resolvedBookmarkURL.standardizedFileURL
        }

        return resolvedBookmarkURL
            .appendingPathComponent(relativePath, isDirectory: true)
            .standardizedFileURL
    }

    private func isPath(_ path: String, equalToOrInside ancestorPath: String) -> Bool {
        guard path == ancestorPath || path.hasPrefix(ancestorPath) else {
            return false
        }

        if ancestorPath == "/" {
            return true
        }

        guard path.count > ancestorPath.count else {
            return true
        }

        let boundaryIndex = path.index(path.startIndex, offsetBy: ancestorPath.count)
        return path[boundaryIndex] == "/"
    }
}
