import AppKit
import Quartz

final class FilePaneViewController: NSViewController {
    let viewModel: FilePaneViewModel
    var activationHandler: ((FilePaneViewController) -> Void)?
    var statusHandler: ((String) -> Void)?

    private let pathBarView = PathBarView()
    private let tableView = FileTableView()
    private let scrollView = NSScrollView()
    private let collectionView = FileCollectionView()
    private let collectionScrollView = FileDropScrollView()
    private let searchField = NSSearchField()
    private let typeFilterPopup = NSPopUpButton()
    private let loadingIndicator = NSProgressIndicator()
    private let contextMenu = NSMenu(title: "File Actions")
    var previewItems: [URL] = []
    private(set) var currentPreviewIndex: Int = 0
    var detailCache: [URL: String] = [:]
    private var previewKeyMonitor: EventMonitorToken?
    private var searchTask: Task<Void, Never>?
    static weak var previewOwner: FilePaneViewController?
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(viewModel: FilePaneViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        self.viewModel.onChange = { [weak self] in self?.reload() }
        self.viewModel.onStatusChange = { [weak self] text in
            self?.statusChanged(text)
            self?.statusHandler?(text)
        }
        self.viewModel.onError = { [weak self] error in self?.showError(error) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let previewKeyMonitor {
            Task { @MainActor in
                previewKeyMonitor.remove()
            }
        }
        searchTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePathBar()
        configureSearchField()
        configureTableView()
        configureTypeFilterPopup()
        configureCollectionView()
        configureLoadingIndicator()
        configurePreviewKeyMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(fileOperationCompleted(_:)), name: .cloverFileOperationCompleted, object: nil)
        viewModel.load()
    }

    override func mouseDown(with event: NSEvent) {
        activationHandler?(self)
        super.mouseDown(with: event)
    }

    func setActive(_ isActive: Bool) {
        view.layer?.borderWidth = isActive ? 2 : 1
        view.layer?.borderColor = (isActive ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    func refresh() {
        viewModel.refresh()
    }

    func open(_ url: URL) {
        viewModel.load(url: url)
    }

    func setViewMode(_ mode: FileViewMode) {
        viewModel.setViewMode(mode)
    }

    @objc func createFolder(_ sender: Any?) {
        activationHandler?(self)
        guard let name = promptForText(title: "New Folder", message: "Enter a folder name:", defaultValue: "Untitled Folder") else { return }
        runOperation {
            try await self.viewModel.createFolder(named: name)
        }
    }

    @objc func renameSelectedItem(_ sender: Any?) {
        activationHandler?(self)
        beginEditingSelectedItemName()
    }

    @objc func previewSelectedItem(_ sender: Any?) {
        activationHandler?(self)
        guard let selectedIndex = selectedItemIndexes().first else { return }
        previewItems = viewModel.items.map(\.url)
        currentPreviewIndex = selectedIndex
        Self.previewOwner = self
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = selectedIndex
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func copySelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, let destinationURL = chooseDestination(title: "Copy To") else { return }
        runOperation {
            try await self.viewModel.copyItems(items, to: destinationURL) { [weak self] conflict in
                await self?.resolveConflict(conflict) ?? .cancel
            }
        }
    }

    @objc func moveSelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, let destinationURL = chooseDestination(title: "Move To") else { return }
        runOperation {
            try await self.viewModel.moveItems(items, to: destinationURL) { [weak self] conflict in
                await self?.resolveConflict(conflict) ?? .cancel
            }
        }
    }

    @objc func trashSelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, confirmTrash(count: items.count) else { return }
        runOperation {
            try await self.viewModel.trashItems(items)
        }
    }

    @objc func focusPathInput(_ sender: Any?) {
        activationHandler?(self)
        pathBarView.beginEditing()
    }

    func setCurrentPreviewIndex(_ index: Int) {
        currentPreviewIndex = index
    }

    private func configurePathBar() {
        pathBarView.translatesAutoresizingMaskIntoConstraints = false
        pathBarView.navigationHandler = { [weak self] url in
            self?.viewModel.load(url: url)
        }
        pathBarView.pathSubmitHandler = { [weak self] path in
            self?.openSubmittedPath(path)
        }
        view.addSubview(pathBarView)
    }

    private func configureTableView() {
        let columns: [(String, String, CGFloat)] = [
            ("name", "Name", 280),
            ("size", "Size", 90),
            ("modified", "Modified", 180)
        ]

        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .medium
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedItem)
        tableView.keyHandler = { [weak self] event in
            self?.handlePaneKeyDown(event) ?? false
        }
        tableView.rightClickHandler = { [weak self] row in
            self?.prepareContextSelection(for: row)
        }
        tableView.dropHandler = { [weak self] draggingInfo, row in
            self?.performMoveDrop(draggingInfo, itemIndex: row) ?? false
        }
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.move, forLocal: false)
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            pathBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            pathBarView.trailingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: -8),
            pathBarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            pathBarView.heightAnchor.constraint(equalToConstant: 26),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: pathBarView.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search"
        searchField.controlSize = .small
        searchField.target = self
        searchField.action = #selector(searchTextChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        view.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: pathBarView.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func configureTypeFilterPopup() {
        typeFilterPopup.translatesAutoresizingMaskIntoConstraints = false
        typeFilterPopup.target = self
        typeFilterPopup.action = #selector(typeFilterChanged(_:))
        typeFilterPopup.controlSize = .small
        view.addSubview(typeFilterPopup)

        NSLayoutConstraint.activate([
            typeFilterPopup.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -18),
            typeFilterPopup.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 2),
            typeFilterPopup.widthAnchor.constraint(equalToConstant: 150)
        ])
    }

    private func configureCollectionView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 112, height: 116)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 14
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)

        collectionView.collectionViewLayout = layout
        collectionView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        collectionView.autoresizingMask = [.width]
        collectionView.register(FileGridItem.self, forItemWithIdentifier: FileGridItem.identifier)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.doubleClickHandler = { [weak self] index in
            self?.openItem(at: index)
        }
        collectionView.keyHandler = { [weak self] event in
            self?.handlePaneKeyDown(event) ?? false
        }
        collectionView.dropHandler = { [weak self] draggingInfo, index in
            self?.performMoveDrop(draggingInfo, itemIndex: index) ?? false
        }
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: false)

        collectionScrollView.documentView = collectionView
        collectionScrollView.hasVerticalScroller = true
        collectionScrollView.isHidden = true
        collectionScrollView.dropHandler = { [weak self] draggingInfo in
            self?.performMoveDrop(draggingInfo, itemIndex: nil) ?? false
        }
        collectionScrollView.registerForDraggedTypes([.fileURL])
        collectionScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionScrollView)

        NSLayoutConstraint.activate([
            collectionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionScrollView.topAnchor.constraint(equalTo: pathBarView.bottomAnchor, constant: 6),
            collectionScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configurePreviewKeyMonitor() {
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handlePreviewPanelKeyDown(event) == true ? nil : event
        }) else { return }
        previewKeyMonitor = EventMonitorToken(monitor)
    }

    private func configureLoadingIndicator() {
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.isDisplayedWhenStopped = false
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.trailingAnchor.constraint(equalTo: pathBarView.trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: pathBarView.centerYAnchor)
        ])
    }

    private func reload() {
        loadingIndicator.stopAnimation(nil)
        detailCache.removeAll()
        pathBarView.update(url: viewModel.currentURL)
        updateTypeFilterPopup()
        tableView.reloadData()
        collectionView.reloadData()
        let isList = viewModel.viewMode == .list
        scrollView.isHidden = !isList
        collectionScrollView.isHidden = isList
        typeFilterPopup.isHidden = !isList
    }

    private func statusChanged(_ text: String) {
        if text.hasPrefix("Loading") {
            loadingIndicator.startAnimation(nil)
        }
    }

    private func showError(_ error: Error) {
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    func selectedItems() -> [FileItem] {
        switch viewModel.viewMode {
        case .list:
            return tableView.selectedRowIndexes.compactMap { viewModel.item(at: $0) }
        case .grid:
            return collectionView.selectionIndexPaths.compactMap { viewModel.item(at: $0.item) }
        }
    }

    private func selectedItemIndexes() -> [Int] {
        switch viewModel.viewMode {
        case .list:
            return tableView.selectedRowIndexes.map { $0 }
        case .grid:
            return collectionView.selectionIndexPaths.map(\.item)
        }
    }

    private func prepareContextSelection(for row: Int) {
        activationHandler?(self)
        guard row >= 0 else {
            tableView.deselectAll(nil)
            return
        }
        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    func performMoveDrop(_ draggingInfo: NSDraggingInfo, itemIndex: Int?) -> Bool {
        guard let urls = draggingInfo.draggingPasteboard.fileURLs, !urls.isEmpty else { return false }
        let destination = dropDestinationURL(itemIndex: itemIndex)
        let movableURLs = urls.filter { $0.deletingLastPathComponent().standardizedFileURL != destination.standardizedFileURL }
        guard !movableURLs.isEmpty else { return false }
        activationHandler?(self)
        runOperation {
            try await self.viewModel.moveFileURLs(movableURLs, to: destination) { [weak self] conflict in
                await self?.resolveConflict(conflict) ?? .cancel
            }
        }
        return true
    }

    func writeDraggedItems(at indexes: [Int], to pasteboard: NSPasteboard) -> Bool {
        let urls = indexes.compactMap { viewModel.item(at: $0)?.url }
        guard !urls.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    private func handlePaneKeyDown(_ event: NSEvent) -> Bool {
        guard event.nonNavigationModifierFlags.isEmpty else { return false }
        switch event.keyCode {
        case 36:
            beginEditingSelectedItemName()
            return true
        case 49:
            previewSelectedItem(nil)
            return true
        default:
            return false
        }
    }

    private func handlePreviewPanelKeyDown(_ event: NSEvent) -> Bool {
        guard event.nonNavigationModifierFlags.isEmpty,
              Self.previewOwner === self,
              let panel = QLPreviewPanel.shared(),
              panel.isVisible,
              !previewItems.isEmpty else {
            return false
        }

        let nextIndex: Int
        switch event.keyCode {
        case 123, 126:
            nextIndex = previewIndex(before: currentPreviewIndex, keyCode: event.keyCode)
        case 124, 125:
            nextIndex = previewIndex(after: currentPreviewIndex, keyCode: event.keyCode)
        default:
            return false
        }

        guard nextIndex != currentPreviewIndex else { return true }
        setCurrentPreviewIndex(nextIndex)
        panel.currentPreviewItemIndex = nextIndex
        selectItemForPreview(at: nextIndex)
        return true
    }

    private func previewIndex(before currentIndex: Int, keyCode: UInt16) -> Int {
        if viewModel.viewMode == .grid, keyCode == 126 {
            return max(currentIndex - gridPreviewColumnCount(), 0)
        }
        return max(currentIndex - 1, 0)
    }

    private func previewIndex(after currentIndex: Int, keyCode: UInt16) -> Int {
        if viewModel.viewMode == .grid, keyCode == 125 {
            return min(currentIndex + gridPreviewColumnCount(), previewItems.count - 1)
        }
        return min(currentIndex + 1, previewItems.count - 1)
    }

    private func gridPreviewColumnCount() -> Int {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return 1 }
        let contentWidth = collectionView.bounds.width - layout.sectionInset.left - layout.sectionInset.right
        let stride = layout.itemSize.width + layout.minimumInteritemSpacing
        return max(Int((contentWidth + layout.minimumInteritemSpacing) / stride), 1)
    }

    private func selectItemForPreview(at index: Int) {
        switch viewModel.viewMode {
        case .list:
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        case .grid:
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.selectionIndexPaths = [indexPath]
            collectionView.selectItems(at: [indexPath], scrollPosition: .centeredVertically)
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        }
    }

    private func beginEditingSelectedItemName() {
        guard let index = selectedItemIndexes().first else { return }
        switch viewModel.viewMode {
        case .list:
            tableView.editColumn(0, row: index, with: nil, select: true)
        case .grid:
            let indexPath = IndexPath(item: index, section: 0)
            guard let item = collectionView.item(at: indexPath) as? FileGridItem else { return }
            item.beginEditingName()
        }
    }

    func renameItem(at index: Int, to newName: String) {
        guard let item = viewModel.item(at: index), !newName.isEmpty, newName != item.name else {
            reload()
            return
        }
        runOperation {
            try await self.viewModel.renameItem(item, to: newName)
        }
    }

    private func dropDestinationURL(itemIndex: Int?) -> URL {
        guard let itemIndex, let item = viewModel.item(at: itemIndex), item.isBrowsableDirectory else {
            return viewModel.currentURL
        }
        return item.url
    }

    private func runOperation(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch CloverError.operationCancelled {
                await MainActor.run {
                    statusChanged("Operation cancelled")
                    statusHandler?("Operation cancelled")
                }
            } catch {
                await MainActor.run { showError(error) }
            }
        }
    }

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let input = NSTextField(string: defaultValue)
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func chooseDestination(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.directoryURL = viewModel.currentURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func confirmTrash(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move to Trash?"
        alert.informativeText = "Move \(count) selected item\(count == 1 ? "" : "s") to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func resolveConflict(_ conflict: FileConflict) async -> FileConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "An item named \"\(conflict.destinationURL.lastPathComponent)\" already exists."
        alert.informativeText = "Choose how Clover should handle the conflict."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .skip
        case .alertThirdButtonReturn:
            return .keepBoth
        default:
            return .cancel
        }
    }

    @objc func openSelectedItem() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        openItem(at: row)
    }

    private func openItem(at index: Int) {
        guard let item = viewModel.item(at: index) else { return }

        if item.isBrowsableDirectory {
            viewModel.load(url: item.url)
        } else {
            Task {
                do {
                    try await viewModel.openItem(item.url)
                } catch {
                    await MainActor.run { showError(error) }
                }
            }
        }
    }

    private func openSubmittedPath(_ path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        viewModel.load(url: url.standardizedFileURL)
    }

    @objc private func fileOperationCompleted(_ notification: Notification) {
        refresh()
    }

    @objc private func typeFilterChanged(_ sender: NSPopUpButton) {
        let selectedTitle = sender.titleOfSelectedItem
        viewModel.setTypeFilter(selectedTitle == "All" ? nil : selectedTitle)
    }

    @objc private func searchTextChanged(_ sender: NSSearchField) {
        searchTask?.cancel()
        let query = sender.stringValue
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.viewModel.setSearchQuery(query)
            }
        }
    }

    private func updateTypeFilterPopup() {
        let selectedFilter = viewModel.typeFilter
        typeFilterPopup.removeAllItems()
        typeFilterPopup.addItem(withTitle: "All")
        for type in viewModel.availableTypeFilters {
            typeFilterPopup.addItem(withTitle: type)
        }
        typeFilterPopup.selectItem(withTitle: selectedFilter ?? "All")
    }

    func detailValue(for item: FileItem, row: Int) -> String {
        if let cachedDetail = detailCache[item.url] {
            return cachedDetail
        }
        Task { [weak self] in
            let detail = await FileGridDetailProvider.detail(for: item)
            await MainActor.run {
                guard let self, self.viewModel.item(at: row)?.url == item.url else { return }
                self.detailCache[item.url] = detail
                self.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 1))
            }
        }
        return item.isBrowsableDirectory ? "--" : (item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
    }
}
