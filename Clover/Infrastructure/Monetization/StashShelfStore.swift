import Foundation

final class StashShelfStore {
    private let fileManager: FileManager
    private let storageURL: URL

    init(fileManager: FileManager = .default, storageURL: URL? = nil) throws {
        self.fileManager = fileManager
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
                .appendingPathComponent("StashShelf.json", isDirectory: false)
        }
    }

    func loadItems() throws -> [StashItem] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder.clover.decode([StashItem].self, from: data)
    }

    func saveItems(_ items: [StashItem]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.clover.encode(deduplicatedItems(items))
        try data.write(to: storageURL, options: .atomic)
    }

    func addItems(_ urls: [URL], bookmarkStore: BookmarkStore) throws -> [StashItem] {
        var items = try loadItems()
        let existingPaths = Set(items.map { Self.canonicalPath(for: $0.path) })
        var stagedPaths = Set<String>()
        let newItems = urls.compactMap { url -> StashItem? in
            let path = Self.canonicalPath(for: url.path)
            guard !existingPaths.contains(path), !stagedPaths.contains(path) else { return nil }
            stagedPaths.insert(path)
            return StashItem(url: url, bookmarkStore: bookmarkStore)
        }
        items.append(contentsOf: newItems)
        try saveItems(items)
        return items
    }

    func removeItem(id: UUID) throws {
        var items = try loadItems()
        items.removeAll { $0.id == id }
        try saveItems(items)
    }

    func clear() throws {
        try saveItems([])
    }

    private func deduplicatedItems(_ items: [StashItem]) -> [StashItem] {
        var seenPaths: Set<String> = []
        return items.filter { item in
            let path = Self.canonicalPath(for: item.path)
            guard !seenPaths.contains(path) else { return false }
            seenPaths.insert(path)
            return true
        }
    }

    private static func canonicalPath(for path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL.path
    }
}
