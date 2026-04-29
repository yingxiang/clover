import Foundation

@MainActor
final class FilePaneViewModel {
    private let provider: any FileProvider
    private let fileOperationService: FileOperationService
    private var loadTask: Task<Void, Never>?

    let id: UUID
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    var sortOption: SortOption = .nameAscending
    var showHiddenFiles = false

    var onChange: (() -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init(
        id: UUID = UUID(),
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        provider: any FileProvider,
        fileOperationService: FileOperationService? = nil
    ) {
        self.id = id
        self.currentURL = currentURL
        self.provider = provider
        self.fileOperationService = fileOperationService ?? FileOperationService(provider: provider)
    }

    deinit {
        loadTask?.cancel()
    }

    func load(url: URL? = nil) {
        loadTask?.cancel()
        let targetURL = url ?? currentURL
        let includeHidden = showHiddenFiles
        let sort = sortOption
        onStatusChange?("Loading \(targetURL.lastPathComponent.isEmpty ? targetURL.path : targetURL.lastPathComponent)...")

        loadTask = Task { [weak self, provider] in
            do {
                let loadedItems = try await provider.listDirectory(at: targetURL)
                try Task.checkCancellation()
                let visibleItems = includeHidden ? loadedItems : loadedItems.filter { !$0.isHidden }
                let sortedItems = FileSortService.sort(visibleItems, by: sort)
                await MainActor.run {
                    guard let self else { return }
                    self.currentURL = targetURL
                    self.items = sortedItems
                    self.onChange?()
                    self.onStatusChange?("\(sortedItems.count) items")
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.onStatusChange?("Cancelled")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.items = []
                    self?.onChange?()
                    self?.onStatusChange?("Unable to load folder")
                    self?.onError?(error)
                }
            }
        }
    }

    func refresh() {
        load(url: currentURL)
    }

    func openItem(_ url: URL) async throws {
        try await provider.openItem(url)
    }

    func createFolder(named name: String) async throws {
        onStatusChange?("Creating folder...")
        _ = try await fileOperationService.createFolder(at: currentURL, name: name)
        onStatusChange?("Folder created")
        refresh()
    }

    func renameItem(_ item: FileItem, to newName: String) async throws {
        onStatusChange?("Renaming \(item.name)...")
        _ = try await fileOperationService.renameItem(at: item.url, to: newName)
        onStatusChange?("Renamed \(item.name)")
        refresh()
    }

    func copyItems(_ items: [FileItem], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?("Copying \(items.count) item\(items.count == 1 ? "" : "s")...")
        try await fileOperationService.copyItems(items.map(\.url), to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?("Copied \(items.count) item\(items.count == 1 ? "" : "s")")
        if destinationURL == currentURL {
            refresh()
        }
    }

    func moveItems(_ items: [FileItem], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?("Moving \(items.count) item\(items.count == 1 ? "" : "s")...")
        try await fileOperationService.moveItems(items.map(\.url), to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?("Moved \(items.count) item\(items.count == 1 ? "" : "s")")
        refresh()
    }

    func trashItems(_ items: [FileItem]) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?("Moving \(items.count) item\(items.count == 1 ? "" : "s") to Trash...")
        try await fileOperationService.trashItems(items.map(\.url))
        onStatusChange?("Moved to Trash")
        refresh()
    }

    func item(at index: Int) -> FileItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }
}
