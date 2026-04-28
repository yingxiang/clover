import Foundation

@MainActor
final class FilePaneViewModel {
    private let provider: any FileProvider
    private var loadTask: Task<Void, Never>?

    let id: UUID
    private(set) var currentURL: URL
    private(set) var items: [FileItem] = []
    var sortOption: SortOption = .nameAscending
    var showHiddenFiles = false

    var onChange: (() -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init(id: UUID = UUID(), currentURL: URL = FileManager.default.homeDirectoryForCurrentUser, provider: any FileProvider) {
        self.id = id
        self.currentURL = currentURL
        self.provider = provider
    }

    deinit {
        loadTask?.cancel()
    }

    func load(url: URL? = nil) {
        if let url {
            currentURL = url
        }

        loadTask?.cancel()
        let targetURL = currentURL
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
                    guard let self, self.currentURL == targetURL else { return }
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

    func item(at index: Int) -> FileItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }
}
