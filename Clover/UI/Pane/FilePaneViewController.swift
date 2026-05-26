import AppKit
import OSLog
import Quartz
import UniformTypeIdentifiers

final class FilePaneViewController: NSViewController {
    let viewModel: FilePaneViewModel
    let directoryAccessStore: DirectoryAccessStore
    var activationHandler: ((FilePaneViewController) -> Void)?
    var statusHandler: ((String) -> Void)?
    var pathChangeHandler: ((FilePaneViewController) -> Void)?
    var commandAvailabilityHandler: ((FilePaneViewController) -> Void)?
    var openDirectoryInNewWindowHandler: ((URL) -> Void)?
    var paneOpenTargetsProvider: ((FilePaneViewController) -> [(paneIndex: Int, displayNumber: Int)])?
    var paneSelectionOverlayHandler: ((Bool, FilePaneViewController, Int?) -> Void)?
    var openDirectoryInPaneHandler: ((Int, URL) -> Void)?

    private let pathBarView = PathBarView()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    let tableView = FileTableView()
    private let scrollView = FileDropScrollView()
    let collectionView = FileCollectionView()
    private let collectionScrollView = FileDropScrollView()
    private let searchField = NSSearchField()
    private let loadingIndicator = NSProgressIndicator()
    private let contextMenu = NSMenu(title: "File Actions")
    var previewItems: [URL] = []
    private(set) var currentPreviewIndex: Int = 0
    var detailCache: [URL: String] = [:]
    private var pendingDetailCallbacks: [URL: [(String) -> Void]] = [:]
    private var previewKeyMonitor: EventMonitorToken?
    private var previewIndexObservation: NSKeyValueObservation?
    private var previewSecurityScopes: [(url: URL, didStartAccessing: Bool)] = []
    var isUpdatingSortIndicators = false
    private var searchTask: Task<Void, Never>?
    var pendingSelectionURLs: [URL] = []
    private var pendingRenameURL: URL?
    private var pendingRenameStartDate: Date?
    var pendingDropExpansionURL: URL?
    var dropExpansionTask: Task<Void, Never>?
    private var pendingCreationKinds: [URL: NewItemKind] = [:]
    private var isPresentingDirectoryAccessPanel = false
    private var didPerformInitialOpen = false
    static weak var previewOwner: FilePaneViewController?
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    init(viewModel: FilePaneViewModel, directoryAccessStore: DirectoryAccessStore) {
        self.viewModel = viewModel
        self.directoryAccessStore = directoryAccessStore
        super.init(nibName: nil, bundle: nil)
        self.viewModel.onChange = { [weak self] in
            guard let self else { return }
            Logger.ui.debug("Pane onChange -> reload. mode=\(self.viewModel.viewMode.rawValue, privacy: .public) items=\(self.viewModel.items.count) rows=\(self.viewModel.listRows.count) pendingRename=\(self.pendingRenameURL?.path ?? "nil", privacy: .public)")
            self.reload()
        }
        self.viewModel.onVisibleItemsChange = { [weak self] in
            self?.applyVisibleItemsChange()
        }
        self.viewModel.onViewModeChange = { [weak self] mode in
            self?.applyViewModeChange(mode)
        }
        self.viewModel.onListMutation = { [weak self] mutation in
            self?.applyListMutation(mutation)
        }
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
        dropExpansionTask?.cancel()
        searchTask?.cancel()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePathBar()
        configureSearchField()
        configureTableView()
        configureCollectionView()
        configureLoadingIndicator()
        configurePreviewKeyMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(fileOperationCompleted(_:)), name: .cloverFileOperationCompleted, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        performInitialOpenIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        activationHandler?(self)
        super.mouseDown(with: event)
    }

    func setActive(_ isActive: Bool) {
        view.layer?.borderWidth = isActive ? 1.25 : 0.75
        view.layer?.borderColor = (isActive ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    func focusBrowser() {
        activationHandler?(self)
        switch viewModel.viewMode {
        case .list:
            view.window?.makeFirstResponder(tableView)
        case .grid:
            view.window?.makeFirstResponder(collectionView)
        }
    }

    func refresh() {
        viewModel.refresh()
    }

    func open(_ url: URL) {
        if requestDirectoryAccessBeforeOpeningIfNeeded(for: url) {
            return
        }
        let targetURL = directoryAccessStore.resolvedURL(for: url) ?? url
        viewModel.load(url: targetURL)
    }

    private func performInitialOpenIfNeeded() {
        guard !didPerformInitialOpen else { return }
        didPerformInitialOpen = true
        open(viewModel.currentURL)
    }

    @objc func goBack(_ sender: Any?) {
        activationHandler?(self)
        viewModel.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        activationHandler?(self)
        viewModel.goForward()
    }

    func setViewMode(_ mode: FileViewMode) {
        viewModel.setViewMode(mode)
    }

    @objc func createFolder(_ sender: Any?) {
        activationHandler?(self)
        beginPendingCreation(of: .folder)
    }

    @objc func createTextFile(_ sender: Any?) {
        activationHandler?(self)
        beginPendingCreation(of: .textFile)
    }

    @objc func createMarkdownFile(_ sender: Any?) {
        activationHandler?(self)
        beginPendingCreation(of: .markdownFile)
    }

    @objc func performNewItemAction(_ sender: NSMenuItem) {
        activationHandler?(self)
        guard let kind = NewItemKind(rawValue: sender.tag) else { return }
        switch kind {
        case .folder:
            createFolder(sender)
        case .textFile:
            createTextFile(sender)
        case .markdownFile:
            createMarkdownFile(sender)
        case .word, .excel, .powerPoint, .keynote, .pages, .numbers, .wps:
            openNewDocumentApp(kind)
        }
    }

    @objc func renameSelectedItem(_ sender: Any?) {
        activationHandler?(self)
        beginEditingSelectedItemName()
    }

    @objc func previewSelectedItem(_ sender: Any?) {
        activationHandler?(self)
        if isControllingVisiblePreviewPanel {
            closePreviewPanel()
            return
        }
        guard let selectedIndex = selectedItemIndexes().first else { return }
        previewItems = previewItemURLsForCurrentMode()
        currentPreviewIndex = selectedIndex
        Self.previewOwner = self
        guard let panel = QLPreviewPanel.shared() else { return }
        startPreviewSecurityScopes(for: previewItems)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        observePreviewIndex(on: panel)
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

    @objc func compressSelectedItems(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty else { return }
        runOperation {
            let archiveURL = try await self.viewModel.createArchive(from: items, in: self.viewModel.currentURL)
            await MainActor.run {
                self.rememberSelection(urls: [archiveURL])
                self.refresh()
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
        configureNavigationButton(backButton, symbol: .back, action: #selector(goBack(_:)), toolTip: L10n.back)
        configureNavigationButton(forwardButton, symbol: .forward, action: #selector(goForward(_:)), toolTip: L10n.forward)
        view.addSubview(backButton)
        view.addSubview(forwardButton)

        pathBarView.translatesAutoresizingMaskIntoConstraints = false
        pathBarView.navigationHandler = { [weak self] url in
            self?.open(url)
        }
        pathBarView.pathSubmitHandler = { [weak self] path in
            self?.openSubmittedPath(path)
        }
        view.addSubview(pathBarView)
    }

    private func configureNavigationButton(_ button: NSButton, symbol: AppSymbol, action: Selector, toolTip: String) {
        button.image = AppIconProvider.image(symbol, accessibilityDescription: toolTip)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func configureTableView() {
        let columns: [(String, String, CGFloat)] = [
            ("name", L10n.name, 280),
            ("size", L10n.size, 90),
            ("type", "\(currentTypeColumnTitle()) ▾", 130),
            ("modified", L10n.modified, 180)
        ]

        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            if let sortDescriptor = sortDescriptor(for: identifier, ascending: true) {
                column.sortDescriptorPrototype = sortDescriptor
            }
            tableView.addTableColumn(column)
        }

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .medium
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedItem)
        let headerView = FileTableHeaderView()
        headerView.typeColumnClickHandler = { [weak self] column in
            self?.showTypeFilterMenu(for: column)
        }
        tableView.headerView = headerView
        tableView.activationHandler = { [weak self] in
            guard let self else { return }
            self.activationHandler?(self)
        }
        tableView.keyHandler = { [weak self] event in
            self?.handlePaneKeyDown(event) ?? false
        }
        tableView.rightClickHandler = { [weak self] row in
            self?.prepareContextSelection(for: row >= 0 ? row : nil)
        }
        tableView.dropHandler = { [weak self] draggingInfo, row in
            self?.performMoveDrop(draggingInfo, itemIndex: row) ?? false
        }
        tableView.dragUpdateHandler = { [weak self] draggingInfo, row in
            self?.updateDropHover(draggingInfo, itemIndex: row) ?? []
        }
        tableView.dragExitHandler = { [weak self] in
            self?.clearDropHover()
        }
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.move, forLocal: false)
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.activationHandler = { [weak self] in
            guard let self else { return }
            self.activationHandler?(self)
        }
        scrollView.rightClickHandler = { [weak self] in self?.prepareContextSelection(for: nil) }
        scrollView.dropHandler = { [weak self] draggingInfo in
            self?.performMoveDrop(draggingInfo, itemIndex: nil) ?? false
        }
        scrollView.registerForDraggedTypes([.fileURL])
        scrollView.menu = contextMenu
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: pathBarView.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: pathBarView.centerYAnchor),
            pathBarView.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 8),
            pathBarView.trailingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: -8),
            pathBarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            pathBarView.heightAnchor.constraint(equalToConstant: 26),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: pathBarView.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func sortDescriptor(for identifier: String, ascending: Bool) -> NSSortDescriptor? {
        switch identifier {
        case "name", "size", "modified":
            return NSSortDescriptor(key: identifier, ascending: ascending)
        default:
            return nil
        }
    }

    private func configureSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.search
        searchField.controlSize = .small
        searchField.target = self
        searchField.action = #selector(searchTextChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(searchField)

        let preferredSearchWidthConstraint = searchField.widthAnchor.constraint(equalToConstant: 180)
        preferredSearchWidthConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: pathBarView.centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            preferredSearchWidthConstraint
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
        collectionView.activationHandler = { [weak self] in
            guard let self else { return }
            self.activationHandler?(self)
        }
        collectionView.doubleClickHandler = { [weak self] index in
            self?.openItem(at: index)
        }
        collectionView.rightClickHandler = { [weak self] index in self?.prepareContextSelection(for: index) }
        collectionView.keyHandler = { [weak self] event in
            self?.handlePaneKeyDown(event) ?? false
        }
        collectionView.dropHandler = { [weak self] draggingInfo, index in
            self?.performMoveDrop(draggingInfo, itemIndex: index) ?? false
        }
        collectionView.dragUpdateHandler = { [weak self] draggingInfo, index in
            self?.updateDropHover(draggingInfo, itemIndex: index) ?? []
        }
        collectionView.dragExitHandler = { [weak self] in
            self?.clearDropHover()
        }
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: false)
        collectionView.menu = contextMenu

        collectionScrollView.documentView = collectionView
        collectionScrollView.hasVerticalScroller = true
        collectionScrollView.isHidden = true
        collectionScrollView.activationHandler = { [weak self] in
            guard let self else { return }
            self.activationHandler?(self)
        }
        collectionScrollView.rightClickHandler = { [weak self] in self?.prepareContextSelection(for: nil) }
        collectionScrollView.dropHandler = { [weak self] draggingInfo in
            self?.performMoveDrop(draggingInfo, itemIndex: nil) ?? false
        }
        collectionScrollView.registerForDraggedTypes([.fileURL])
        collectionScrollView.menu = contextMenu
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
        Logger.ui.debug("reload begin. mode=\(self.viewModel.viewMode.rawValue, privacy: .public) items=\(self.viewModel.items.count) rows=\(self.viewModel.listRows.count) selectionCount=\(self.selectedItems().count) pendingRename=\(self.pendingRenameURL?.path ?? "nil", privacy: .public)")
        loadingIndicator.stopAnimation(nil)
        detailCache.removeAll()
        pathBarView.update(url: viewModel.currentURL)
        updateNavigationButtons()
        updateSortIndicators()
        updateTypeColumnTitle()
        tableView.reloadData()
        collectionView.reloadData()
        restorePendingSelectionIfNeeded()
        beginPendingRenameIfNeeded()
        let isList = viewModel.viewMode == .list
        scrollView.isHidden = !isList
        collectionScrollView.isHidden = isList
        updateCommandAvailability()
        pathChangeHandler?(self)
        Logger.ui.debug("reload end. mode=\(self.viewModel.viewMode.rawValue, privacy: .public) items=\(self.viewModel.items.count) rows=\(self.viewModel.listRows.count) selectedIndexes=\(self.selectedItemIndexes().description, privacy: .public)")
    }

    private func applyVisibleItemsChange() {
        Logger.ui.debug("visible items changed. mode=\(self.viewModel.viewMode.rawValue, privacy: .public) items=\(self.viewModel.items.count) rows=\(self.viewModel.listRows.count)")
        updateTypeColumnTitle()
        switch viewModel.viewMode {
        case .list:
            tableView.reloadData()
        case .grid:
            collectionView.reloadData()
        }
        restorePendingSelectionIfNeeded()
        updateCommandAvailability()
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = viewModel.canGoBack
        forwardButton.isEnabled = viewModel.canGoForward
    }

    private func updateSortIndicators() {
        let descriptor: NSSortDescriptor?
        switch viewModel.sortOption {
        case .nameAscending:
            descriptor = sortDescriptor(for: "name", ascending: true)
        case .nameDescending:
            descriptor = sortDescriptor(for: "name", ascending: false)
        case .sizeAscending:
            descriptor = sortDescriptor(for: "size", ascending: true)
        case .sizeDescending:
            descriptor = sortDescriptor(for: "size", ascending: false)
        case .dateAscending:
            descriptor = sortDescriptor(for: "modified", ascending: true)
        case .dateDescending:
            descriptor = sortDescriptor(for: "modified", ascending: false)
        default:
            descriptor = nil
        }
        isUpdatingSortIndicators = true
        tableView.sortDescriptors = descriptor.map { [$0] } ?? []
        isUpdatingSortIndicators = false
    }

    private func statusChanged(_ text: String) {
        if text.hasPrefix("Loading") {
            loadingIndicator.startAnimation(nil)
        }
    }

    func showError(_ error: Error) {
        if requestDirectoryAccessIfNeeded(for: error) {
            return
        }
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func requestDirectoryAccessIfNeeded(for error: Error) -> Bool {
        guard !isPresentingDirectoryAccessPanel,
              let window = view.window,
              let requestedURL = requestedDirectoryURL(for: error),
              shouldRequestDirectoryAccess(for: requestedURL) else {
            return false
        }

        Logger.ui.debug("Directory access panel after error url=\(requestedURL.standardizedFileURL.path, privacy: .public)")
        let panel = NSOpenPanel()
        panel.title = L10n.grantFolderAccess
        panel.message = L10n.grantFolderAccessMessage(requestedURL.lastPathComponent.isEmpty ? requestedURL.path : requestedURL.lastPathComponent)
        panel.prompt = L10n.grantAccess
        panel.directoryURL = panelDirectoryURL(for: requestedURL)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        isPresentingDirectoryAccessPanel = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isPresentingDirectoryAccessPanel = false
            Logger.ui.debug("Directory access panel result response=\(response.rawValue, privacy: .public) selected=\(panel.url?.standardizedFileURL.path ?? "nil", privacy: .public)")
            guard response == .OK, let selectedURL = panel.url else { return }

            do {
                try self.directoryAccessStore.saveAccess(to: selectedURL)
            } catch {
                Logger.ui.error("Failed to persist directory access bookmark: \(error.localizedDescription, privacy: .public)")
            }
            self.open(requestedURL)
        }
        return true
    }

    private func requestDirectoryAccessBeforeOpeningIfNeeded(for url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let shouldRequest = shouldProactivelyRequestDirectoryAccess(for: url)
        guard !isPresentingDirectoryAccessPanel,
              shouldRequest,
              let window = view.window else {
            return false
        }

        guard !directoryAccessStore.hasSavedAccess(to: standardizedURL) else {
            return false
        }

        let requestedURL = standardizedURL
        Logger.ui.debug("Directory access panel proactive url=\(requestedURL.path, privacy: .public)")
        let panel = NSOpenPanel()
        panel.title = L10n.grantFolderAccess
        panel.message = L10n.grantFolderAccessMessage(requestedURL.lastPathComponent)
        panel.prompt = L10n.grantAccess
        panel.directoryURL = requestedURL
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        isPresentingDirectoryAccessPanel = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isPresentingDirectoryAccessPanel = false
            Logger.ui.debug("Directory access panel result response=\(response.rawValue, privacy: .public) selected=\(panel.url?.standardizedFileURL.path ?? "nil", privacy: .public)")
            guard response == .OK, let selectedURL = panel.url else { return }

            do {
                try self.directoryAccessStore.saveAccess(to: selectedURL)
            } catch {
                Logger.ui.error("Failed to persist directory access bookmark: \(error.localizedDescription, privacy: .public)")
            }
            self.open(requestedURL)
        }
        return true
    }

    private func requestedDirectoryURL(for error: Error) -> URL? {
        switch error {
        case CloverError.directoryNotFound(let url), CloverError.permissionDenied(let url):
            return url.standardizedFileURL
        default:
            return nil
        }
    }

    private func shouldRequestDirectoryAccess(for url: URL) -> Bool {
        shouldRequireUserSelectedAccess(for: url)
    }

    private func shouldProactivelyRequestDirectoryAccess(for url: URL) -> Bool {
        shouldRequireUserSelectedAccess(for: url)
    }

    private func shouldRequireUserSelectedAccess(for url: URL) -> Bool {
        url.isFileURL
    }

    private func panelDirectoryURL(for requestedURL: URL) -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: requestedURL.path) {
            return requestedURL
        }
        return requestedURL.deletingLastPathComponent()
    }

    func selectedItems() -> [FileItem] {
        switch viewModel.viewMode {
        case .list:
            return tableView.selectedRowIndexes.compactMap { viewModel.item(at: $0) }
        case .grid:
            return collectionView.selectionIndexPaths.compactMap { viewModel.item(at: $0.item) }
        }
    }

    func selectedItemIndexes() -> [Int] {
        switch viewModel.viewMode {
        case .list:
            return tableView.selectedRowIndexes.map { $0 }
        case .grid:
            return collectionView.selectionIndexPaths.map(\.item)
        }
    }

    func performMoveDrop(_ draggingInfo: NSDraggingInfo, itemIndex: Int?) -> Bool {
        defer { clearDropHover() }
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
            togglePreviewPanel()
            return true
        default:
            return false
        }
    }

    func handlePreviewPanelKeyDown(_ event: NSEvent) -> Bool {
        guard event.nonNavigationModifierFlags.isEmpty,
              Self.previewOwner === self,
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else {
            return false
        }

        switch event.keyCode {
        case 49:
            closePreviewPanel()
            return true
        case 123, 124, 125, 126:
            guard let nextIndex = previewIndex(from: currentPreviewIndex, keyCode: event.keyCode) else {
                return false
            }
            showPreview(at: nextIndex, in: panel)
            return true
        default:
            return false
        }
    }

    private var isControllingVisiblePreviewPanel: Bool {
        guard Self.previewOwner === self,
              let panel = QLPreviewPanel.shared() else { return false }
        return panel.isVisible
    }

    private func togglePreviewPanel() {
        if isControllingVisiblePreviewPanel {
            closePreviewPanel()
        } else {
            previewSelectedItem(nil)
        }
    }

    private func closePreviewPanel() {
        guard Self.previewOwner === self,
              let panel = QLPreviewPanel.shared() else { return }
        panel.close()
        stopControllingPreviewPanel(panel)
    }

    private func observePreviewIndex(on panel: QLPreviewPanel) {
        previewIndexObservation = panel.observe(\.currentPreviewItemIndex, options: [.new]) { [weak self] panel, _ in
            Task { @MainActor in
                self?.syncSelectionWithPreviewPanel(panel)
            }
        }
    }

    private func syncSelectionWithPreviewPanel(_ panel: QLPreviewPanel) {
        guard Self.previewOwner === self,
              panel.isVisible else { return }
        let index = panel.currentPreviewItemIndex
        guard previewItems.indices.contains(index) else { return }
        currentPreviewIndex = index
        selectItemForPreview(at: index)
    }

    func stopControllingPreviewPanel(_ panel: QLPreviewPanel) {
        guard Self.previewOwner === self else { return }
        previewIndexObservation = nil
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        stopPreviewSecurityScopes()
        Self.previewOwner = nil
    }

    private func startPreviewSecurityScopes(for urls: [URL]) {
        stopPreviewSecurityScopes()
        var scopedPaths: Set<String> = []
        for url in urls {
            guard let securityScopeURL = directoryAccessStore.securityScopeURL(for: url) else { continue }
            let path = securityScopeURL.path
            guard scopedPaths.insert(path).inserted else { continue }
            previewSecurityScopes.append((url: securityScopeURL, didStartAccessing: securityScopeURL.startAccessingSecurityScopedResource()))
        }
    }

    private func stopPreviewSecurityScopes() {
        for scope in previewSecurityScopes where scope.didStartAccessing {
            scope.url.stopAccessingSecurityScopedResource()
        }
        previewSecurityScopes.removeAll()
    }

    private func showPreview(at index: Int, in panel: QLPreviewPanel) {
        guard index != currentPreviewIndex else { return }
        setCurrentPreviewIndex(index)
        panel.currentPreviewItemIndex = index
        selectItemForPreview(at: index)
    }

    private func previewIndex(from currentIndex: Int, keyCode: UInt16) -> Int? {
        guard !previewItems.isEmpty else { return nil }
        let nextIndex: Int
        switch (viewModel.viewMode, keyCode) {
        case (.list, 126):
            nextIndex = currentIndex - 1
        case (.list, 125):
            nextIndex = currentIndex + 1
        case (.grid, 123):
            nextIndex = currentIndex - 1
        case (.grid, 124):
            nextIndex = currentIndex + 1
        case (.grid, 126):
            nextIndex = currentIndex - gridPreviewColumnCount()
        case (.grid, 125):
            nextIndex = currentIndex + gridPreviewColumnCount()
        default:
            return nil
        }
        return min(max(nextIndex, 0), previewItems.count - 1)
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
        Logger.ui.debug("beginEditingSelectedItemName index=\(index) mode=\(self.viewModel.viewMode.rawValue, privacy: .public)")
        switch viewModel.viewMode {
        case .list:
            tableView.editColumn(0, row: index, with: nil, select: true)
            DispatchQueue.main.async { [weak self] in
                self?.selectListEditingNameStem(at: index)
            }
        case .grid:
            let indexPath = IndexPath(item: index, section: 0)
            guard let item = collectionView.item(at: indexPath) as? FileGridItem else { return }
            item.beginEditingName()
        }
    }

    private func rememberCreatedItemForRenaming(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        pendingRenameURL = standardizedURL
        pendingRenameStartDate = nil
        rememberSelection(urls: [standardizedURL])
        Logger.ui.debug("rememberCreatedItemForRenaming url=\(standardizedURL.path, privacy: .public)")
    }

    private func beginPendingRenameIfNeeded() {
        guard let pendingRenameURL else { return }
        let selectedURLs = Set(selectedItems().map { $0.url.standardizedFileURL })
        guard selectedURLs.contains(pendingRenameURL) else { return }
        Logger.ui.debug("beginPendingRenameIfNeeded matched url=\(pendingRenameURL.path, privacy: .public)")
        guard pendingRenameStartDate == nil else { return }
        pendingRenameStartDate = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingRenameURL != nil else { return }
            self.beginEditingSelectedItemName()
        }
    }

    func renameItem(at index: Int, to newName: String, didCancel: Bool = false, textMovement: Int? = nil) {
        guard let item = viewModel.item(at: index) else { return }
        let standardizedURL = item.url.standardizedFileURL

        if let kind = pendingCreationKinds[standardizedURL] {
            handlePendingCreationRename(
                for: item,
                kind: kind,
                newName: newName,
                didCancel: didCancel,
                textMovement: textMovement
            )
            return
        }

        guard !newName.isEmpty, newName != item.name else {
            if let item = viewModel.item(at: index) {
                rememberSelection(urls: [item.url])
            }
            refresh()
            return
        }
        let renamedURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        rememberSelection(urls: [renamedURL])
        runOperation {
            try await self.viewModel.renameItem(item, to: newName)
        }
    }

    private func beginPendingCreation(of kind: NewItemKind) {
        let placeholderItem = makePendingPlaceholderItem(for: kind)
        pendingCreationKinds[placeholderItem.url.standardizedFileURL] = kind
        Logger.ui.debug("beginPendingCreation kind=\(String(describing: kind), privacy: .public) placeholder=\(placeholderItem.url.path, privacy: .public) name=\(placeholderItem.name, privacy: .public)")
        rememberCreatedItemForRenaming(at: placeholderItem.url)
        viewModel.insertItem(placeholderItem, notify: false)
        insertPendingItemIntoVisibleView(at: placeholderItem.url)
    }

    private func makePendingPlaceholderItem(for kind: NewItemKind) -> FileItem {
        let isDirectory = kind == .folder
        let placeholderURL = viewModel.currentURL.appendingPathComponent(".clover-pending-\(UUID().uuidString)", isDirectory: isDirectory)
        return FileItem(
            url: placeholderURL,
            name: kind.defaultName,
            isDirectory: isDirectory,
            size: isDirectory ? nil : 0,
            modificationDate: Date(),
            creationDate: Date(),
            typeIdentifier: placeholderTypeIdentifier(for: kind),
            isHidden: false
        )
    }

    private func placeholderTypeIdentifier(for kind: NewItemKind) -> String? {
        switch kind {
        case .folder:
            return UTType.folder.identifier
        case .textFile:
            return UTType.plainText.identifier
        case .markdownFile:
            return UTType(filenameExtension: "md")?.identifier
        default:
            return nil
        }
    }

    private func handlePendingCreationRename(
        for item: FileItem,
        kind: NewItemKind,
        newName: String,
        didCancel: Bool,
        textMovement: Int?
    ) {
        let placeholderURL = item.url.standardizedFileURL
        Logger.ui.debug("handlePendingCreationRename kind=\(String(describing: kind), privacy: .public) placeholder=\(placeholderURL.path, privacy: .public) newName=\(newName, privacy: .public) didCancel=\(didCancel) movement=\(textMovement ?? -1)")

        if shouldIgnoreTransientPendingRenameEnd(
            for: item,
            newName: newName,
            didCancel: didCancel,
            textMovement: textMovement
        ) {
            Logger.ui.debug("pending creation ignored transient end-edit placeholder=\(placeholderURL.path, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.pendingCreationKinds[placeholderURL] != nil else { return }
                self.rememberSelection(urls: [placeholderURL])
                self.beginEditingSelectedItemName()
            }
            return
        }

        if didCancel || newName.isEmpty {
            pendingCreationKinds.removeValue(forKey: placeholderURL)
            pendingRenameURL = nil
            pendingRenameStartDate = nil
            viewModel.removeItem(with: placeholderURL, notify: false)
            removePendingItemFromVisibleView(at: placeholderURL)
            return
        }

        let finalName = resolvedPendingCreationName(for: kind, enteredName: newName)
        pendingCreationKinds.removeValue(forKey: placeholderURL)
        pendingRenameURL = nil
        pendingRenameStartDate = nil
        runOperation {
            let createdURL: URL
            switch kind {
            case .folder:
                createdURL = try await self.viewModel.createFolder(named: finalName)
            case .textFile, .markdownFile:
                createdURL = try await self.viewModel.createTextFile(named: finalName)
            default:
                throw CloverError.unsupportedOperation
            }
            await MainActor.run {
                Logger.ui.debug("pending creation committed placeholder=\(placeholderURL.path, privacy: .public) created=\(createdURL.path, privacy: .public)")
                self.viewModel.removeItem(with: placeholderURL, notify: false)
                self.removePendingItemFromVisibleView(at: placeholderURL)
                self.rememberSelection(urls: [createdURL])
                self.refresh()
                if kind == .textFile || kind == .markdownFile {
                    Task {
                        do {
                            try await self.viewModel.openItem(createdURL)
                        } catch {
                            await MainActor.run {
                                self.showError(error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func shouldIgnoreTransientPendingRenameEnd(
        for item: FileItem,
        newName: String,
        didCancel: Bool,
        textMovement: Int?
    ) -> Bool {
        guard !didCancel,
              newName == item.name,
              !isExplicitPendingRenameCommitMovement(textMovement) else {
            return false
        }
        guard let pendingRenameURL,
              pendingRenameURL == item.url.standardizedFileURL,
              let pendingRenameStartDate else {
            return false
        }
        return Date().timeIntervalSince(pendingRenameStartDate) < 0.75
    }

    private func isExplicitPendingRenameCommitMovement(_ textMovement: Int?) -> Bool {
        guard let textMovement else { return false }
        return textMovement == NSReturnTextMovement
            || textMovement == NSTabTextMovement
            || textMovement == NSBacktabTextMovement
    }

    private func resolvedPendingCreationName(for kind: NewItemKind, enteredName: String) -> String {
        switch kind {
        case .textFile:
            return enteredName.contains(".") ? enteredName : "\(enteredName).txt"
        case .markdownFile:
            return enteredName.contains(".") ? enteredName : "\(enteredName).md"
        default:
            return enteredName
        }
    }

    private func insertPendingItemIntoVisibleView(at url: URL) {
        Logger.ui.debug("insertPendingItemIntoVisibleView url=\(url.path, privacy: .public) mode=\(self.viewModel.viewMode.rawValue, privacy: .public)")
        switch viewModel.viewMode {
        case .list:
            guard let row = viewModel.listRowIndex(for: url) else {
                Logger.ui.error("insertPendingItemIntoVisibleView fallback reload list url=\(url.path, privacy: .public)")
                reload()
                return
            }
            Logger.ui.debug("insertPendingItemIntoVisibleView list row=\(row)")
            tableView.beginUpdates()
            tableView.insertRows(at: IndexSet(integer: row), withAnimation: [])
            tableView.endUpdates()
        case .grid:
            guard let item = viewModel.gridItemIndex(for: url) else {
                Logger.ui.error("insertPendingItemIntoVisibleView fallback reload grid url=\(url.path, privacy: .public)")
                reload()
                return
            }
            Logger.ui.debug("insertPendingItemIntoVisibleView grid item=\(item)")
            collectionView.performBatchUpdates({
                collectionView.insertItems(at: [IndexPath(item: item, section: 0)])
            })
        }
        restorePendingSelectionIfNeeded()
        beginPendingRenameIfNeeded()
        updateCommandAvailability()
    }

    private func selectListEditingNameStem(at row: Int) {
        guard let item = viewModel.item(at: row),
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileListNameCellView,
              let textField = cell.textField,
              let editor = textField.currentEditor() else { return }
        editor.selectedRange = editableFileNameSelectionRange(for: item.name, isDirectory: item.isDirectory)
    }

    private func removePendingItemFromVisibleView(at url: URL) {
        Logger.ui.debug("removePendingItemFromVisibleView url=\(url.path, privacy: .public) mode=\(self.viewModel.viewMode.rawValue, privacy: .public)")
        switch viewModel.viewMode {
        case .list:
            tableView.reloadData()
        case .grid:
            collectionView.reloadData()
        }
        updateCommandAvailability()
    }

    private func applyListMutation(_ mutation: FilePaneListMutation) {
        guard viewModel.viewMode == .list else {
            reload()
            return
        }
        Logger.ui.debug("applyListMutation kind=\(String(describing: mutation.kind), privacy: .public) rows=\(mutation.rows.description, privacy: .public) reload=\(mutation.reloadedRows.description, privacy: .public)")
        tableView.beginUpdates()
        switch mutation.kind {
        case .insert:
            tableView.insertRows(at: mutation.rows, withAnimation: .effectGap)
        case .remove:
            tableView.removeRows(at: mutation.rows, withAnimation: .effectFade)
        }
        if !mutation.reloadedRows.isEmpty {
            tableView.reloadData(forRowIndexes: mutation.reloadedRows, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        }
        tableView.endUpdates()
        updateCommandAvailability()
    }

    private func applyViewModeChange(_ mode: FileViewMode) {
        let isList = mode == .list
        scrollView.isHidden = !isList
        collectionScrollView.isHidden = isList
        if isList {
            updateTypeColumnTitle()
        }
        restorePendingSelectionIfNeeded()
        updateCommandAvailability()
        pathChangeHandler?(self)
    }

    private func dropDestinationURL(itemIndex: Int?) -> URL {
        guard let itemIndex, let item = viewModel.item(at: itemIndex), item.isBrowsableDirectory else {
            return viewModel.currentURL
        }
        return item.url
    }

    func runOperation(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch CloverError.operationCancelled {
                await MainActor.run {
                    statusChanged(L10n.operationCancelled)
                    statusHandler?(L10n.operationCancelled)
                }
            } catch {
                await MainActor.run { showError(error) }
            }
        }
    }

    func chooseDestination(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = L10n.choose
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
        alert.messageText = L10n.moveToTrashPrompt
        alert.informativeText = L10n.moveItemsToTrashMessage(count)
        alert.addButton(withTitle: L10n.moveToTrashAction)
        alert.addButton(withTitle: L10n.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    func resolveConflict(_ conflict: FileConflict) async -> FileConflictResolution {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.conflictExists(conflict.destinationURL.lastPathComponent)
        alert.informativeText = L10n.conflictChoice
        alert.addButton(withTitle: L10n.replace)
        alert.addButton(withTitle: L10n.skip)
        alert.addButton(withTitle: L10n.keepBoth)
        alert.addButton(withTitle: L10n.cancel)

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
        let index: Int
        switch viewModel.viewMode {
        case .list:
            index = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        case .grid:
            index = selectedItemIndexes().first ?? -1
        }
        openItem(at: index)
    }

    private func openItem(at index: Int) {
        guard let item = viewModel.item(at: index) else { return }

        if item.isBrowsableDirectory {
            open(item.url)
        } else if item.isExtractableArchive {
            extractArchiveAndSelectResult(item)
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

    private func extractArchiveAndSelectResult(_ item: FileItem) {
        runOperation {
            let extractedURL = try await self.viewModel.extractArchive(item)
            await MainActor.run {
                self.rememberSelection(urls: [extractedURL])
                self.refresh()
            }
        }
    }

    private func openSubmittedPath(_ path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        open(url.standardizedFileURL)
    }

    private func openNewDocumentApp(_ kind: NewItemKind) {
        guard let appURL = kind.appURL else {
            showError(CloverError.unsupportedOperation)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in
                    self.showError(error)
                }
            }
        }
    }

    @objc private func fileOperationCompleted(_ notification: Notification) {
        let affectedDirectories = notification.cloverAffectedDirectories
        let movedItemURLs = notification.cloverMovedItemURLs
        guard !affectedDirectories.isEmpty else {
            if !movedItemURLs.isEmpty {
                viewModel.removeCachedItems(with: movedItemURLs, notify: false)
            }
            refresh()
            return
        }
        let relevantDirectories = viewModel.relevantDirectoryURLsForRefresh()
        let shouldRefresh = affectedDirectories.contains { relevantDirectories.contains($0.standardizedFileURL) }
        if shouldRefresh {
            if !movedItemURLs.isEmpty {
                viewModel.removeCachedItems(with: movedItemURLs, notify: false)
            }
            refresh()
        }
    }

    func updateCommandAvailability() {
        view.window?.toolbar?.validateVisibleItems()
        commandAvailabilityHandler?(self)
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

    func detailValue(for item: FileItem, row: Int) -> String {
        let placeholder = detailPlaceholderValue(for: item)
        loadDetailIfNeeded(for: item, tableRow: row, collectionIndex: nil, completion: nil)
        return placeholder
    }

    func detailPlaceholderValue(for item: FileItem) -> String {
        if let cachedDetail = detailCache[item.url] {
            return cachedDetail
        }
        return item.isBrowsableDirectory ? "--" : (item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
    }

    func loadDetailIfNeeded(
        for item: FileItem,
        tableRow: Int?,
        collectionIndex: Int?,
        completion: ((String) -> Void)?
    ) {
        let url = item.url
        if let cachedDetail = detailCache[url] {
            completion?(cachedDetail)
            return
        }

        if var callbacks = pendingDetailCallbacks[url] {
            if let completion {
                callbacks.append(completion)
            }
            pendingDetailCallbacks[url] = callbacks
            return
        }

        pendingDetailCallbacks[url] = completion.map { [$0] } ?? []

        Task(priority: .userInitiated) { [weak self] in
            let detail = await FileGridDetailProvider.detail(for: item, directoryAccessStore: self?.directoryAccessStore)
            await MainActor.run {
                guard let self else { return }
                self.detailCache[url] = detail
                let callbacks = self.pendingDetailCallbacks.removeValue(forKey: url) ?? []
                if let tableRow, self.viewModel.item(at: tableRow)?.url == item.url {
                    self.tableView.reloadData(forRowIndexes: IndexSet(integer: tableRow), columnIndexes: IndexSet(integer: 1))
                }
                if let collectionIndex,
                   self.viewModel.item(at: collectionIndex)?.url == item.url,
                   let gridItem = self.collectionView.item(at: collectionIndex) as? FileGridItem {
                    gridItem.setDetail(detail)
                }
                callbacks.forEach { $0(detail) }
            }
        }
    }
}
