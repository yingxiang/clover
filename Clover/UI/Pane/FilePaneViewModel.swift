import Foundation
import UniformTypeIdentifiers

struct FilePaneListRow {
    let item: FileItem
    let depth: Int
    let isExpanded: Bool
}

struct FilePaneListMutation {
    enum Kind {
        case insert
        case remove
    }

    let kind: Kind
    let rows: IndexSet
    let reloadedRows: IndexSet
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
    var onViewModeChange: ((FileViewMode) -> Void)?
    var onListMutation: ((FilePaneListMutation) -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init(
        id: UUID = UUID(),
        currentURL: URL = UserDirectories.homeURL,
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
        onStatusChange?(L10n.loadingFolder(targetURL.lastPathComponent.isEmpty ? targetURL.path : targetURL.lastPathComponent))

        loadTask = Task { [weak self, provider] in
            do {
                let loadedItems = try await provider.listDirectory(at: targetURL)
                try Task.checkCancellation()
                let visibleItems = includeHidden ? loadedItems : loadedItems.filter { !$0.isHidden }
                let sortedItems = FileSortService.sort(visibleItems, by: sort)
                await MainActor.run {
                    guard let self else { return }
                    let isNavigatingToDifferentDirectory = targetURL.standardizedFileURL != previousURL.standardizedFileURL
                    if isNavigatingToDifferentDirectory {
                        self.backHistory.append(previousURL)
                        self.forwardHistory.removeAll()
                    }
                    self.currentURL = targetURL
                    if isNavigatingToDifferentDirectory {
                        self.typeFilter = nil
                        self.resetListExpansion()
                    }
                    self.allItems = sortedItems
                    self.applyFilters()
                    self.onChange?()
                    self.onStatusChange?("\(self.items.count) items")
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.onStatusChange?(L10n.cancelled)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.allItems = []
                    self?.items = []
                    self?.onChange?()
                    self?.onStatusChange?(L10n.unableToLoadFolder)
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
        onViewModeChange?(mode)
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
        Array(Set(allItems.map { FileItemPresentation.typeKey(for: $0) })).sorted {
            FileItemPresentation.localizedTypeName(for: $0).localizedStandardCompare(
                FileItemPresentation.localizedTypeName(for: $1)
            ) == .orderedAscending
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

    func createFolder(named name: String) async throws -> URL {
        onStatusChange?(L10n.creatingFolder)
        let createdURL = try await fileOperationService.createFolder(at: currentURL, name: name)
        onStatusChange?(L10n.folderCreated)
        return createdURL
    }

    func createTextFile(named name: String) async throws -> URL {
        onStatusChange?(L10n.creatingFile)
        let createdURL = try await fileOperationService.createFile(at: currentURL, name: name, contents: Data())
        onStatusChange?(L10n.fileCreated)
        return createdURL
    }

    func insertItem(_ item: FileItem, notify: Bool = true) {
        let url = item.url
        allItems.removeAll { $0.url.standardizedFileURL == url.standardizedFileURL }
        allItems.append(item)
        allItems = FileSortService.sort(allItems, by: sortOption)
        applyFilters()
        if notify {
            onChange?()
        }
    }

    func removeItem(with url: URL, notify: Bool = true) {
        let standardizedURL = url.standardizedFileURL
        allItems.removeAll { $0.url.standardizedFileURL == standardizedURL }
        items.removeAll { $0.url.standardizedFileURL == standardizedURL }
        listRows.removeAll { $0.item.url.standardizedFileURL == standardizedURL }
        if notify {
            onChange?()
        }
    }

    func listRowIndex(for url: URL) -> Int? {
        let standardizedURL = url.standardizedFileURL
        return listRows.firstIndex { $0.item.url.standardizedFileURL == standardizedURL }
    }

    func gridItemIndex(for url: URL) -> Int? {
        let standardizedURL = url.standardizedFileURL
        return items.firstIndex { $0.url.standardizedFileURL == standardizedURL }
    }

    func relevantDirectoryURLsForRefresh() -> Set<URL> {
        var urls = Set([currentURL.standardizedFileURL])
        urls.formUnion(expandedDirectoryURLs.map(\.standardizedFileURL))
        return urls
    }

    func renameItem(_ item: FileItem, to newName: String) async throws {
        onStatusChange?(L10n.renamingItem(item.name))
        let renamedURL = try await fileOperationService.renameItem(at: item.url, to: newName)
        onStatusChange?(L10n.renamedItem(item.name))
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: [item.url.deletingLastPathComponent(), renamedURL.deletingLastPathComponent()]
        )
    }

    func copyItems(_ items: [FileItem], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?(L10n.copyingItems(items.count))
        let sourceDirectories = items.map { $0.url.deletingLastPathComponent() }
        try await fileOperationService.copyItems(items.map(\.url), to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?(L10n.copiedItems(items.count))
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: sourceDirectories + [destinationURL]
        )
    }

    func copyFileURLs(_ urls: [URL], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !urls.isEmpty else { return }
        onStatusChange?(L10n.copyingItems(urls.count))
        let sourceDirectories = urls.map { $0.deletingLastPathComponent() }
        try await fileOperationService.copyItems(urls, to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?(L10n.copiedItems(urls.count))
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: sourceDirectories + [destinationURL]
        )
    }

    func moveItems(_ items: [FileItem], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?(L10n.movingItems(items.count))
        let sourceDirectories = items.map { $0.url.deletingLastPathComponent() }
        try await fileOperationService.moveItems(items.map(\.url), to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?(L10n.movedItems(items.count))
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: sourceDirectories + [destinationURL]
        )
    }

    func moveFileURLs(_ urls: [URL], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        guard !urls.isEmpty else { return }
        onStatusChange?(L10n.movingItems(urls.count))
        let sourceDirectories = urls.map { $0.deletingLastPathComponent() }
        try await fileOperationService.moveItems(urls, to: destinationURL, conflictResolver: conflictResolver)
        onStatusChange?(L10n.movedItems(urls.count))
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: sourceDirectories + [destinationURL]
        )
    }

    func trashItems(_ items: [FileItem]) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?(L10n.movingItemsToTrash(items.count))
        let affectedDirectories = items.map { $0.url.deletingLastPathComponent() }
        try await fileOperationService.trashItems(items.map(\.url))
        onStatusChange?(L10n.movedToTrashStatus)
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: affectedDirectories
        )
    }

    func deleteItemsPermanently(_ items: [FileItem]) async throws {
        guard !items.isEmpty else { return }
        onStatusChange?(L10n.deletingItems(items.count))
        let affectedDirectories = items.map { $0.url.deletingLastPathComponent() }
        try await fileOperationService.deleteItemsPermanently(items.map(\.url))
        onStatusChange?(L10n.deletedItems(items.count))
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: affectedDirectories
        )
    }

    func setLabelNumber(_ labelNumber: Int?, for items: [FileItem]) async throws {
        guard !items.isEmpty else { return }
        try await fileOperationService.setLabelNumber(labelNumber, for: items.map(\.url))
        onStatusChange?(L10n.updatedLabels)
        NotificationCenter.default.postCloverFileOperationCompleted(
            affectedDirectories: items.map { $0.url.deletingLastPathComponent() }
        )
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
            emitListMutation(beforeRows: listRows, afterMutationFor: url) {
                self.rebuildListRows()
            }
            return
        }
        Task { [weak self, provider] in
            do {
                let loadedItems = try await provider.listDirectory(at: url)
                await MainActor.run {
                    guard let self else { return }
                    self.directoryChildren[url] = self.filteredSortedItems(loadedItems)
                    self.expandedDirectoryURLs.insert(url)
                    self.emitListMutation(beforeRows: self.listRows, afterMutationFor: url) {
                        self.rebuildListRows()
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.onError?(error)
                }
            }
        }
    }

    private func applyFilters() {
        if let typeFilter,
           !Set(allItems.map({ FileItemPresentation.typeKey(for: $0) })).contains(typeFilter) {
            self.typeFilter = nil
        }
        var filteredItems = allItems
        if let typeFilter {
            filteredItems = filteredItems.filter { FileItemPresentation.typeKey(for: $0) == typeFilter }
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

    private func inferredTypeIdentifier(for url: URL, isDirectory: Bool) -> String? {
        if isDirectory {
            return UTType.folder.identifier
        }
        guard !url.pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: url.pathExtension)?.identifier
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
            filteredItems = filteredItems.filter { FileItemPresentation.typeKey(for: $0) == typeFilter }
        }
        if !searchQuery.isEmpty {
            filteredItems = filteredItems.filter { FileSearchMatcher.matches($0, query: searchQuery, caseSensitive: searchCaseSensitive) }
        }
        return FileSortService.sort(filteredItems, by: sortOption)
    }

    private func collapseListDirectory(_ url: URL) {
        emitListMutation(beforeRows: listRows, afterMutationFor: url) {
            self.collapseListDirectorySilently(url)
        }
    }

    private func collapseListDirectorySilently(_ url: URL) {
        expandedDirectoryURLs.remove(url)
        let childURLs = directoryChildren[url]?.map(\.url) ?? []
        for childURL in childURLs {
            collapseListDirectorySilently(childURL)
        }
        rebuildListRows()
    }

    private func emitListMutation(beforeRows: [FilePaneListRow], afterMutationFor toggledURL: URL, update: () -> Void) {
        let beforeURLs = beforeRows.map { $0.item.url.standardizedFileURL }
        update()
        let afterURLs = listRows.map { $0.item.url.standardizedFileURL }
        let changedRows = IndexSet(
            listRows.enumerated().compactMap { index, row in
                row.item.url.standardizedFileURL == toggledURL.standardizedFileURL ? index : nil
            }
        )
        if afterURLs.count >= beforeURLs.count {
            let insertedRows = insertedRowIndexes(from: beforeURLs, to: afterURLs)
            onListMutation?(
                FilePaneListMutation(kind: .insert, rows: insertedRows, reloadedRows: changedRows)
            )
        } else {
            let removedRows = removedRowIndexes(from: beforeURLs, to: afterURLs)
            onListMutation?(
                FilePaneListMutation(kind: .remove, rows: removedRows, reloadedRows: changedRows)
            )
        }
    }

    private func insertedRowIndexes(from beforeURLs: [URL], to afterURLs: [URL]) -> IndexSet {
        var beforeIndex = 0
        var inserted = IndexSet()
        for (afterIndex, url) in afterURLs.enumerated() {
            if beforeIndex < beforeURLs.count, beforeURLs[beforeIndex] == url {
                beforeIndex += 1
            } else {
                inserted.insert(afterIndex)
            }
        }
        return inserted
    }

    private func removedRowIndexes(from beforeURLs: [URL], to afterURLs: [URL]) -> IndexSet {
        var afterIndex = 0
        var removed = IndexSet()
        for (beforeIndex, url) in beforeURLs.enumerated() {
            if afterIndex < afterURLs.count, afterURLs[afterIndex] == url {
                afterIndex += 1
            } else {
                removed.insert(beforeIndex)
            }
        }
        return removed
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
        onStatusChange?(L10n.loadingFolder(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent))

        loadTask = Task { [weak self, provider] in
            do {
                let loadedItems = try await provider.listDirectory(at: url)
                try Task.checkCancellation()
                let visibleItems = includeHidden ? loadedItems : loadedItems.filter { !$0.isHidden }
                let sortedItems = FileSortService.sort(visibleItems, by: sort)
                await MainActor.run {
                    guard let self else { return }
                    let isNavigatingToDifferentDirectory = url.standardizedFileURL != self.currentURL.standardizedFileURL
                    self.currentURL = url
                    if isNavigatingToDifferentDirectory {
                        self.typeFilter = nil
                        self.resetListExpansion()
                    }
                    self.allItems = sortedItems
                    self.applyFilters()
                    self.onChange?()
                    self.onStatusChange?("\(self.items.count) items")
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.onStatusChange?(L10n.cancelled)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.allItems = []
                    self?.items = []
                    self?.onChange?()
                    self?.onStatusChange?(L10n.unableToLoadFolder)
                    self?.onError?(error)
                }
            }
        }
    }
}
