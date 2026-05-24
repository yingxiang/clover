import Foundation

final class WorkspaceStore {
    private let fileManager: FileManager
    private let workspaceDirectoryURL: URL
    private let defaultWorkspaceURL: URL
    private let bookmarkStore: BookmarkStore

    init(
        fileManager: FileManager = .default,
        workspaceURL: URL? = nil,
        bookmarkStore: BookmarkStore = BookmarkStore()
    ) throws {
        self.fileManager = fileManager
        self.bookmarkStore = bookmarkStore
        if let workspaceURL {
            self.defaultWorkspaceURL = workspaceURL
            self.workspaceDirectoryURL = workspaceURL.deletingLastPathComponent()
        } else {
            let supportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.workspaceDirectoryURL = supportURL
                .appendingPathComponent("Clover", isDirectory: true)
                .appendingPathComponent("Workspaces", isDirectory: true)
            self.defaultWorkspaceURL = workspaceDirectoryURL.appendingPathComponent("default.json", isDirectory: false)
        }
    }

    func loadDefaultWorkspace() throws -> Workspace? {
        guard fileManager.fileExists(atPath: defaultWorkspaceURL.path) else { return nil }
        let data = try Data(contentsOf: defaultWorkspaceURL)
        return try JSONDecoder.clover.decode(Workspace.self, from: data)
    }

    func saveDefaultWorkspace(_ workspace: Workspace) throws {
        try createWorkspaceDirectoryIfNeeded()
        let data = try JSONEncoder.clover.encode(workspace)
        try data.write(to: defaultWorkspaceURL, options: .atomic)
    }

    func loadSavedWorkspaces() throws -> [Workspace] {
        try createWorkspaceDirectoryIfNeeded()
        let urls = try workspaceURLs().filter { $0.lastPathComponent != defaultWorkspaceURL.lastPathComponent }
        var workspaces: [Workspace] = []
        for url in urls where fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            workspaces.append(try JSONDecoder.clover.decode(Workspace.self, from: data))
        }
        return workspaces.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    func saveWorkspace(_ workspace: Workspace, named name: String) throws -> Workspace {
        try createWorkspaceDirectoryIfNeeded()
        let renamed = Workspace(
            id: UUID(),
            name: name,
            layout: workspace.layout,
            panes: workspace.panes,
            windowFrame: workspace.windowFrame,
            sidebarWidth: workspace.sidebarWidth,
            isSidebarCollapsed: workspace.isSidebarCollapsed,
            createdAt: workspace.createdAt,
            updatedAt: Date()
        )
        let url = workspaceURL(for: renamed.id)
        let data = try JSONEncoder.clover.encode(renamed)
        try data.write(to: url, options: .atomic)
        return renamed
    }

    func renameWorkspace(id: UUID, to name: String) throws -> Workspace? {
        guard var workspace = try loadWorkspace(id: id) else { return nil }
        workspace.name = name
        workspace.updatedAt = Date()
        try save(workspace)
        return workspace
    }

    func deleteWorkspace(id: UUID) throws {
        let url = workspaceURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func loadWorkspace(id: UUID) throws -> Workspace? {
        let url = workspaceURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.clover.decode(Workspace.self, from: data)
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

        return UserDirectories.homeURL
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

    private func createWorkspaceDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: workspaceDirectoryURL, withIntermediateDirectories: true)
    }

    private func workspaceURLs() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: workspaceDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
    }

    private func workspaceURL(for id: UUID) -> URL {
        workspaceDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: false).appendingPathExtension("json")
    }

    private func save(_ workspace: Workspace) throws {
        let url = workspaceURL(for: workspace.id)
        let data = try JSONEncoder.clover.encode(workspace)
        try data.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static var clover: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var clover: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
