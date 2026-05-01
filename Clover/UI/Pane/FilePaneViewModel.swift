import Foundation

struct FilePaneListRow {
    let item: FileItem
    let depth: Int
    let isExpanded: Bool
}

@MainActor
final class FilePaneViewModel {
    private let provider: any FileProvider
    private let fileOperationService: FileOperationService
    private var loadTask: Task<Void, Never>?

    let id: UUID
    private(set) var currentURL: URL
    private var allItems: [FileItem] = []
    private(set) var items: [FileItem] = []
    private(set) var listRows: [FilePaneListRow] = []
    private(set) var viewMode: FileViewMode = .list
    var sortOption: SortOption = .nameAscending
    var showHiddenFiles = false
    private(set) var typeFilter: String?
    private(set) var searchQuery = ""
    var searchCaseSensitive = false
    private var backHistory: [URL] = []
    private var forwardHistory: [URL] = []
    private var expandedDirectoryURLs: Set<URL> = []
    private var directoryChildren: [URL: [FileItem]] = [:]

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
        let previousURL = currentURL
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
                    if targetURL != previousURL {
                        self.backHistory.append(previousURL)
                        self.forwardHistory.removeAll()
                    }
                    self.currentURL = targetURL
                    self.resetListExpansion()
                    self.allItems = sortedItems
                    self.applyFilters()
                    self.onChange?()
                    self.onStatusChange?("\(self.items.count) items")
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.onStatusChange?("Cancelled")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.allItems = []
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

    var canGoBack: Bool {
        !backHistory.isEmpty
    }

    var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    func goBack() {
        guard let url = backHistory.popLast() else { return }
        forwardHistory.append(currentURL)
        loadWithoutRecordingHistory(url: url)
    }

    func goForward() {
        guard let url = forwardHistory.popLast() else { return }
        backHistory.append(currentURL)
        loadWithoutRecordingHistory(url: url)
    }

    func setViewMode(_ mode: FileViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        onChange?()
    }

    func restoreState(currentURL: URL, viewMode: FileViewMode, sortOption: SortOption) {
        self.currentURL = currentURL
        self.viewMode = viewMode
        self.sortOption = sortOption
        typeFilter = nil
        searchQuery = ""
        resetListExpansion()
    }

    func setSortOption(_ sortOption: SortOption) {
        self.sortOption = sortOption
        allItems = FileSortService.sort(allItems, by: sortOption)
        directoryChildren = directoryChildren.mapValues { FileSortService.sort($0, by: sortOption) }
        applyFilters()
        onChange?()
        onStatusChange?("\(items.count) items")
    }

    func workspaceState(using store: WorkspaceStore) -> PaneState {
        store.paneState(id: id, currentURL: currentURL, viewMode: viewMode, sortOption: sortOption)
    }

    var availableTypeFilters: [String] {
        Array(Set(allItems.map { FileItemPresentation.typeName(for: $0) })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func setTypeFilter(_ typeFilter: String?) {
        self.typeFilter = typeFilter
        applyFilters()
        onChange?()
        onStatusChange?("\(items.count) items")
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilters()
        onChange?()
        onStatusChange?("\(items.count) items")
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
        NotificationCenter.default.post(name: .cloverFileOperationCompleted, object: nil)
        if destinationURL == currentURL {
            refresh()
        }
    }

    func moveItems(_ items: [FileItem], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?("Moving \(items.count) item\(items.count == 1 ? "" : "s")...")
        try await fileOperationService.moveItems(items.map(\.url), to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?("Moved \(items.count) item\(items.count == 1 ? "" : "s")")
        NotificationCenter.default.post(name: .cloverFileOperationCompleted, object: nil)
        refresh()
    }

    func moveFileURLs(_ urls: [URL], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !urls.isEmpty else { return }
        onStatusChange?("Moving \(urls.count) item\(urls.count == 1 ? "" : "s")...")
        try await fileOperationService.moveItems(urls, to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?("Moved \(urls.count) item\(urls.count == 1 ? "" : "s")")
        NotificationCenter.default.post(name: .cloverFileOperationCompleted, object: nil)
        refresh()
    }

    func trashItems(_ items: [FileItem]) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?("Moving \(items.count) item\(items.count == 1 ? "" : "s") to Trash...")
        try await fileOperationService.trashItems(items.map(\.url))
        onStatusChange?("Moved to Trash")
        NotificationCenter.default.post(name: .cloverFileOperationCompleted, object: nil)
        refresh()
    }

    func item(at index: Int) -> FileItem? {
        if viewMode == .list {
            guard listRows.indices.contains(index) else { return nil }
            return listRows[index].item
        }
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    func listDepth(at row: Int) -> Int {
        guard listRows.indices.contains(row) else { return 0 }
        return listRows[row].depth
    }

    func listRowCanExpand(at row: Int) -> Bool {
        guard let item = item(at: row) else { return false }
        return item.isBrowsableDirectory
    }

    func listRowIsExpanded(at row: Int) -> Bool {
        guard listRows.indices.contains(row) else { return false }
        return listRows[row].isExpanded
    }

    func toggleListExpansion(at row: Int) {
        guard viewMode == .list,
              listRows.indices.contains(row),
              listRows[row].item.isBrowsableDirectory else { return }
        let url = listRows[row].item.url
        if expandedDirectoryURLs.contains(url) {
            collapseListDirectory(url)
            return
        }
        if let children = directoryChildren[url] {
            expandedDirectoryURLs.insert(url)
            directoryChildren[url] = FileSortService.sort(children, by: sortOption)
            rebuildListRows()
            onChange?()
            return
        }
        Task { [weak self, provider] in
            do {
                let loadedItems = try await provider.listDirectory(at: url)
                await MainActor.run {
                    guard let self else { return }
                    self.directoryChildren[url] = self.filteredSortedItems(loadedItems)
                    self.expandedDirectoryURLs.insert(url)
                    self.rebuildListRows()
                    self.onChange?()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.rebuildListRows()
                    self.onChange?()
                    self.onError?(error)
                }
            }
        }
    }

    private func applyFilters() {
        var filteredItems = allItems
        if let typeFilter {
            filteredItems = filteredItems.filter { FileItemPresentation.typeName(for: $0) == typeFilter }
        }
        if !searchQuery.isEmpty {
            filteredItems = filteredItems.filter { FileSearchMatcher.matches($0, query: searchQuery, caseSensitive: searchCaseSensitive) }
        }
        items = filteredItems
        rebuildListRows()
    }

    private func filteredSortedItems(_ loadedItems: [FileItem]) -> [FileItem] {
        let visibleItems = showHiddenFiles ? loadedItems : loadedItems.filter { !$0.isHidden }
        return FileSortService.sort(visibleItems, by: sortOption)
    }

    private func rebuildListRows() {
        var rows: [FilePaneListRow] = []
        appendListRows(from: items, depth: 0, to: &rows)
        listRows = rows
    }

    private func appendListRows(from sourceItems: [FileItem], depth: Int, to rows: inout [FilePaneListRow]) {
        for item in sourceItems {
            let isExpanded = expandedDirectoryURLs.contains(item.url)
            rows.append(FilePaneListRow(item: item, depth: depth, isExpanded: isExpanded))
            guard isExpanded, let children = directoryChildren[item.url] else { continue }
            appendListRows(from: filteredChildren(children), depth: depth + 1, to: &rows)
        }
    }

    private func filteredChildren(_ children: [FileItem]) -> [FileItem] {
        var filteredItems = children
        if let typeFilter {
            filteredItems = filteredItems.filter { FileItemPresentation.typeName(for: $0) == typeFilter }
        }
        if !searchQuery.isEmpty {
            filteredItems = filteredItems.filter { FileSearchMatcher.matches($0, query: searchQuery, caseSensitive: searchCaseSensitive) }
        }
        return FileSortService.sort(filteredItems, by: sortOption)
    }

    private func collapseListDirectory(_ url: URL) {
        expandedDirectoryURLs.remove(url)
        let childURLs = directoryChildren[url]?.map(\.url) ?? []
        for childURL in childURLs {
            collapseListDirectory(childURL)
        }
        rebuildListRows()
        onChange?()
    }

    private func resetListExpansion() {
        expandedDirectoryURLs.removeAll()
        directoryChildren.removeAll()
        listRows.removeAll()
    }

    private func loadWithoutRecordingHistory(url: URL) {
        loadTask?.cancel()
        let includeHidden = showHiddenFiles
        let sort = sortOption
        onStatusChange?("Loading \(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)...")

        loadTask = Task { [weak self, provider] in
            do {
                let loadedItems = try await provider.listDirectory(at: url)
                try Task.checkCancellation()
                let visibleItems = includeHidden ? loadedItems : loadedItems.filter { !$0.isHidden }
                let sortedItems = FileSortService.sort(visibleItems, by: sort)
                await MainActor.run {
                    guard let self else { return }
                    self.currentURL = url
                    self.resetListExpansion()
                    self.allItems = sortedItems
                    self.applyFilters()
                    self.onChange?()
                    self.onStatusChange?("\(self.items.count) items")
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.onStatusChange?("Cancelled")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.allItems = []
                    self?.items = []
                    self?.onChange?()
                    self?.onStatusChange?("Unable to load folder")
                    self?.onError?(error)
                }
            }
        }
    }
}
