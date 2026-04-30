import Foundation

final class WorkspaceStore {
    private let fileManager: FileManager
    private let workspaceURL: URL
    private let bookmarkStore: BookmarkStore

    init(
        fileManager: FileManager = .default,
        workspaceURL: URL? = nil,
        bookmarkStore: BookmarkStore = BookmarkStore()
    ) throws {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore
        if let workspaceURL {
            self.workspaceURL = workspaceURL
        } else {
            let supportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.workspaceURL = supportURL
                .appendingPathComponent("Clover", isDirectory: true)
                .appendingPathComponent("Workspaces", isDirectory: true)
                .appendingPathComponent("default.json", isDirectory: false)
        }
    }

    func loadDefaultWorkspace() throws -> Workspace? {
        guard fileManager.fileExists(atPath: workspaceURL.path) else { return nil }
        let data = try Data(contentsOf: workspaceURL)
        return try JSONDecoder.clover.decode(Workspace.self, from: data)
    }

    func saveDefaultWorkspace(_ workspace: Workspace) throws {
        try fileManager.createDirectory(
            at: workspaceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.clover.encode(workspace)
        try data.write(to: workspaceURL, options: .atomic)
    }

    func paneState(
        id: UUID,
        currentURL: URL,
        viewMode: FileViewMode,
        sortOption: SortOption,
        selectedFileNames: [String] = [],
        backHistory: [String] = [],
        forwardHistory: [String] = []
    ) -> PaneState {
        let bookmark = try? bookmarkStore.bookmarkData(for: currentURL)
        return PaneState(
            id: id,
            currentURLBookmark: bookmark,
            currentPath: currentURL.path,
            viewMode: viewMode,
            sortOption: sortOption,
            selectedFileNames: selectedFileNames,
            backHistory: backHistory,
            forwardHistory: forwardHistory
        )
    }

    func resolvedURL(for paneState: PaneState) -> URL {
        if let bookmark = paneState.currentURLBookmark,
           let url = try? bookmarkStore.resolveBookmark(bookmark),
           directoryExists(at: url) {
            return url
        }

        let url = URL(fileURLWithPath: (paneState.currentPath as NSString).expandingTildeInPath, isDirectory: true)
        if directoryExists(at: url) {
            return url
        }

        return fileManager.homeDirectoryForCurrentUser
    }

    private func directoryExists(at url: URL) -> Bool {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private extension JSONEncoder {
    static var clover: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var clover: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
