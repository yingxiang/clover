import AppKit
import UniformTypeIdentifiers

private enum ApplicationMenuIconLoader {
    nonisolated(unsafe) private static let cache = NSCache<NSURL, NSImage>()

    static func cachedIcon(for appURL: URL) -> NSImage? {
        cache.object(forKey: appURL as NSURL)
    }

    @MainActor
    static func loadIcon(for appURL: URL, accessibilityDescription: String?, completion: @escaping @MainActor (NSImage?) -> Void) {
        let cacheKey = appURL as NSURL
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let image = AppIconProvider.menuFileImage(appURL.path, accessibilityDescription: accessibilityDescription)
            if let image {
                cache.setObject(image, forKey: cacheKey)
            }
            Task { @MainActor in
                completion(image)
            }
        }
    }
}

extension FilePaneViewController: NSMenuDelegate, @preconcurrency NSSharingServicePickerDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let selectedCount = selectedItems().count
        let pasteTitle = pasteMenuTitle()
        if selectedCount == 0 {
            addNewItems(to: menu, nested: false)
            menu.addItem(.separator())
            if let pasteTitle {
                addMenuItem(pasteTitle, action: #selector(pasteFromPasteboard(_:)), to: menu, symbol: .paste)
            }
            addMenuItem(L10n.openInTerminal, action: #selector(openSelectedItemsInTerminal(_:)), to: menu, symbol: .terminal)
            addMenuItem(L10n.refresh, action: #selector(refreshFromContextMenu(_:)), to: menu, symbol: .refresh)
            return
        }

        addNewItems(to: menu, nested: true)
        menu.addItem(.separator())

        addMenuItem(L10n.open, action: #selector(openSelectedItem), to: menu, enabled: selectedCount == 1, symbol: .open)
        if let openWithMenu = openWithMenu() {
            addSubmenuItem(L10n.openWith, submenu: openWithMenu, to: menu, symbol: .openWith)
        }
        addMenuItem(L10n.openInTerminal, action: #selector(openSelectedItemsInTerminal(_:)), to: menu, enabled: selectedCount == 1, symbol: .terminal)
        menu.addItem(.separator())
        if let shareItem = shareMenuItem() {
            menu.addItem(shareItem)
        }
        addMenuItem(L10n.airDrop, action: #selector(sendSelectedItemsViaAirDrop(_:)), to: menu, enabled: canPerformFileAction(#selector(sendSelectedItemsViaAirDrop(_:))), symbol: .airDrop)
        addMenuItem(L10n.showInfo, action: #selector(showSelectedItemsInfo(_:)), to: menu, symbol: .info)
        addMenuItem(L10n.showInFinder, action: #selector(revealSelectedItemsInFinder(_:)), to: menu, symbol: .finder)
        menu.addItem(.separator())
        addMenuItem(L10n.rename, action: #selector(renameSelectedItem(_:)), to: menu, enabled: selectedCount == 1, symbol: .rename)
        addMenuItem(L10n.copy, action: #selector(copySelectionToPasteboard(_:)), to: menu, symbol: .copy)
        if let pasteTitle {
            addMenuItem(pasteTitle, action: #selector(pasteFromPasteboard(_:)), to: menu, symbol: .paste)
        }
        addMenuItem(L10n.copyTo, action: #selector(copySelectedItems(_:)), to: menu, symbol: .copy)
        addMenuItem(L10n.moveTo, action: #selector(moveSelectedItems(_:)), to: menu, symbol: .move)
        addMenuItem(L10n.copyPath, action: #selector(copySelectedItemPaths(_:)), to: menu, symbol: .file)
        menu.addItem(.separator())
        addSubmenuItem(L10n.tags, submenu: tagsMenu(), to: menu, symbol: .tag)
        menu.addItem(.separator())
        addMenuItem(L10n.moveToTrash, action: #selector(trashSelectedItems(_:)), to: menu, symbol: .trash)
        addMenuItem(L10n.deleteImmediately, action: #selector(deleteSelectedItemsPermanently(_:)), to: menu, symbol: .deleteImmediately)
    }

    func canPerformFileAction(_ action: Selector) -> Bool {
        switch action {
        case #selector(refreshFromContextMenu(_:)),
             #selector(createFolder(_:)),
             #selector(createTextFile(_:)),
             #selector(createMarkdownFile(_:)),
             #selector(performNewItemAction(_:)),
             #selector(goBack(_:)),
             #selector(goForward(_:)),
             #selector(focusPathInput(_:)):
            return true
        case #selector(renameSelectedItem(_:)):
            return selectedItems().count == 1
        case #selector(openSelectedItemsInTerminal(_:)):
            return true
        case #selector(copySelectionToPasteboard(_:)),
             #selector(copySelectedItems(_:)),
             #selector(moveSelectedItems(_:)),
             #selector(trashSelectedItems(_:)),
             #selector(deleteSelectedItemsPermanently(_:)),
             #selector(revealSelectedItemsInFinder(_:)),
             #selector(copySelectedItemPaths(_:)),
             #selector(showSelectedItemsInfo(_:)):
            return !selectedItems().isEmpty
        case #selector(pasteFromPasteboard(_:)):
            return pasteboardFileURLs().isEmpty == false
        case #selector(selectAllItems(_:)):
            return viewModel.viewMode == .list ? tableView.numberOfRows > 0 : collectionView.numberOfItems(inSection: 0) > 0
        case #selector(showShareMenuProxy(_:)):
            return !selectedFileURLs().isEmpty
        case #selector(sendSelectedItemsViaAirDrop(_:)):
            return airDropSharingService() != nil && !selectedFileURLs().isEmpty
        case #selector(openSelectedItem):
            return selectedItems().count == 1
        default:
            return true
        }
    }

    @objc func copySelectionToPasteboard(_ sender: Any?) {
        activationHandler?(self)
        let urls = selectedFileURLs()
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        statusHandler?("Copied \(urls.count) item\(urls.count == 1 ? "" : "s")")
        updateCommandAvailability()
    }

    @objc func pasteFromPasteboard(_ sender: Any?) {
        activationHandler?(self)
        let urls = pasteboardFileURLs()
        guard !urls.isEmpty else { return }
        runOperation {
            try await self.viewModel.copyFileURLs(urls, to: self.viewModel.currentURL) { [weak self] conflict in
                await self?.resolveConflict(conflict) ?? .cancel
            }
        }
    }

    @objc func selectAllItems(_ sender: Any?) {
        activationHandler?(self)
        switch viewModel.viewMode {
        case .list:
            tableView.selectRowIndexes(IndexSet(integersIn: 0..<tableView.numberOfRows), byExtendingSelection: false)
        case .grid:
            let indexPaths = Set((0..<collectionView.numberOfItems(inSection: 0)).map { IndexPath(item: $0, section: 0) })
            collectionView.selectionIndexPaths = indexPaths
            collectionView.selectItems(at: indexPaths, scrollPosition: [])
        }
        updateCommandAvailability()
    }

    @objc func deleteSelectedItemsPermanently(_ sender: Any?) {
        activationHandler?(self)
        let items = selectedItems()
        guard !items.isEmpty, confirmPermanentDelete(count: items.count) else { return }
        runOperation {
            try await self.viewModel.deleteItemsPermanently(items)
        }
    }

    @objc func revealSelectedItemsInFinder(_ sender: Any?) {
        activationHandler?(self)
        let urls = selectedFileURLs()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func copySelectedItemPaths(_ sender: Any?) {
        activationHandler?(self)
        let paths = selectedFileURLs().map(\.path)
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        statusHandler?("Copied path\(paths.count == 1 ? "" : "s")")
    }

    @objc func openSelectedItemsInTerminal(_ sender: Any?) {
        activationHandler?(self)
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        let targetURL: URL
        if let item = selectedItems().first {
            targetURL = item.isBrowsableDirectory ? item.url : item.url.deletingLastPathComponent()
        } else {
            targetURL = viewModel.currentURL
        }
        NSWorkspace.shared.open(
            [targetURL],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                Task { @MainActor in
                    self.showError(error)
                }
            }
        }
    }

    @objc func showSelectedItemsInfo(_ sender: Any?) {
        activationHandler?(self)
        let urls = selectedFileURLs()
        guard !urls.isEmpty else { return }
        do {
            try showFinderInfo(for: urls)
        } catch {
            showError(error)
        }
    }

    @objc func sendSelectedItemsViaAirDrop(_ sender: Any?) {
        activationHandler?(self)
        guard let service = airDropSharingService() else { return }
        withSelectedFileSecurityScopes { urls in
            guard service.canPerform(withItems: urls) else { return }
            service.perform(withItems: urls)
        }
    }

    @objc func performSharingService(_ sender: NSMenuItem) {
        activationHandler?(self)
        guard let service = sender.representedObject as? NSSharingService else { return }
        withSelectedFileSecurityScopes { urls in
            guard service.canPerform(withItems: urls) else { return }
            service.perform(withItems: urls)
        }
    }

    @objc func showShareMenuProxy(_ sender: Any?) {
        activationHandler?(self)
        showShareMenu(relativeTo: sender as? NSView)
    }

    func showShareMenu(relativeTo view: NSView?) {
        guard let picker = sharePicker() else { return }
        let anchorView = view ?? self.view
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    @objc func openSelectedItemsWithApp(_ sender: NSMenuItem) {
        activationHandler?(self)
        guard let appURL = sender.representedObject as? URL else { return }
        let urls = selectedFileURLs()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                Task { @MainActor in
                    self.showError(error)
                }
            }
        }
    }

    @objc func searchAppsInAppStore(_ sender: Any?) {
        activationHandler?(self)
        guard let query = appStoreSearchQuery(),
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "macappstore://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?mt=12&term=\(encodedQuery)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func openSelectedItemsWithOtherApp(_ sender: Any?) {
        activationHandler?(self)
        let panel = NSOpenPanel()
        panel.title = L10n.chooseApplication
        panel.prompt = L10n.choose
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let appURL = panel.url else { return }

        let item = NSMenuItem()
        item.representedObject = appURL
        openSelectedItemsWithApp(item)
    }

    @objc func setSelectedItemsTag(_ sender: NSMenuItem) {
        activationHandler?(self)
        let labelNumber = sender.representedObject as? Int
        let items = selectedItems()
        guard !items.isEmpty else { return }
        runOperation {
            try await self.viewModel.setLabelNumber(labelNumber, for: items)
        }
    }

    @objc private func refreshFromContextMenu(_ sender: Any?) {
        activationHandler?(self)
        refresh()
    }

    func prepareContextSelection(for index: Int?) {
        activationHandler?(self)
        switch viewModel.viewMode {
        case .list:
            guard let row = index, row >= 0 else {
                tableView.deselectAll(nil)
                updateCommandAvailability()
                return
            }
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        case .grid:
            guard let item = index, item >= 0 else {
                collectionView.deselectAll(nil)
                updateCommandAvailability()
                return
            }
            let indexPath = IndexPath(item: item, section: 0)
            if !collectionView.selectionIndexPaths.contains(indexPath) {
                collectionView.deselectAll(nil)
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
            }
        }
        updateCommandAvailability()
    }

    func rememberSelection(urls: [URL]) {
        pendingSelectionURLs = urls.map(\.standardizedFileURL)
    }

    func restorePendingSelectionIfNeeded() {
        guard !pendingSelectionURLs.isEmpty else { return }
        let urls = Set(pendingSelectionURLs)
        pendingSelectionURLs.removeAll()

        switch viewModel.viewMode {
        case .list:
            let indexes = viewModel.listRows.enumerated().compactMap { index, row in
                urls.contains(row.item.url.standardizedFileURL) ? index : nil
            }
            guard !indexes.isEmpty else { return }
            tableView.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
            tableView.scrollRowToVisible(indexes[0])
        case .grid:
            let indexPaths = viewModel.items.enumerated().compactMap { index, item in
                urls.contains(item.url.standardizedFileURL) ? IndexPath(item: index, section: 0) : nil
            }
            guard !indexPaths.isEmpty else { return }
            let selection = Set(indexPaths)
            collectionView.selectionIndexPaths = selection
            collectionView.scrollToItems(at: selection, scrollPosition: .centeredVertically)
        }
        updateCommandAvailability()
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool = true, symbol: AppSymbol? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        if let symbol {
            item.image = AppIconProvider.menuImage(symbol, accessibilityDescription: title)
        }
        menu.addItem(item)
    }

    private func addSubmenuItem(_ title: String, submenu: NSMenu, to menu: NSMenu, symbol: AppSymbol? = nil) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let symbol {
            item.image = AppIconProvider.menuImage(symbol, accessibilityDescription: title)
        }
        menu.addItem(item)
    }

    private func newItemsMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.new)
        for kind in availableNewItemKinds() {
            let item = NSMenuItem(title: kind.title, action: #selector(performNewItemAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            item.image = newItemMenuImage(for: kind)
            menu.addItem(item)
        }
        return menu
    }

    private func addNewItems(to menu: NSMenu, nested: Bool) {
        if nested {
            addSubmenuItem(L10n.new, submenu: newItemsMenu(), to: menu, symbol: .folderPlus)
            return
        }

        for kind in availableNewItemKinds() {
            let item = NSMenuItem(title: kind.title, action: #selector(performNewItemAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            item.image = newItemMenuImage(for: kind)
            menu.addItem(item)
        }
    }

    private func availableNewItemKinds() -> [NewItemKind] {
        NewItemKind.allCases.filter(\.isAvailable)
    }

    private func openWithMenu() -> NSMenu? {
        guard let url = selectedFileURLs().first else { return nil }
        let applicationURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
        let defaultApplicationURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        let otherApplications = applicationURLs.filter { $0 != defaultApplicationURL }
        let hasAppStore = appStoreSearchQuery() != nil
        let hasOther = true
        guard defaultApplicationURL != nil || !otherApplications.isEmpty || hasAppStore || hasOther else { return nil }

        let menu = NSMenu(title: L10n.openWith)
        if let defaultApplicationURL {
            addMenuSectionHeader(L10n.defaultApplication, to: menu)
            menu.addItem(makeApplicationMenuItem(appURL: defaultApplicationURL))
        }

        if !otherApplications.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            addMenuSectionHeader(L10n.recommendedApplications, to: menu)
            for appURL in otherApplications {
                menu.addItem(makeApplicationMenuItem(appURL: appURL))
            }
        }

        if hasAppStore || hasOther {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
        }
        if hasAppStore {
            addMenuItem(L10n.openInAppStore, action: #selector(searchAppsInAppStore(_:)), to: menu, symbol: .appStore)
        }
        if hasOther {
            addMenuItem(L10n.otherApplication, action: #selector(openSelectedItemsWithOtherApp(_:)), to: menu, symbol: .otherApp)
        }
        return menu
    }

    private func makeApplicationMenuItem(appURL: URL) -> NSMenuItem {
        let item = NSMenuItem(title: applicationMenuTitle(for: appURL), action: #selector(openSelectedItemsWithApp(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = appURL
        item.image = ApplicationMenuIconLoader.cachedIcon(for: appURL)
            ?? AppIconProvider.menuImage(.applications, accessibilityDescription: item.title)
        ApplicationMenuIconLoader.loadIcon(for: appURL, accessibilityDescription: item.title) { [weak item] image in
            guard let item, item.representedObject as? URL == appURL, let image else { return }
            item.image = image
        }
        return item
    }

    private func applicationMenuTitle(for appURL: URL) -> String {
        let title = appURL.deletingPathExtension().lastPathComponent
        return title.isEmpty ? appURL.lastPathComponent : title
    }

    private func addMenuSectionHeader(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func shareMenuItem() -> NSMenuItem? {
        guard let picker = sharePicker() else { return nil }
        let item = picker.standardShareMenuItem
        item.title = L10n.share
        item.image = AppIconProvider.menuImage(.share, accessibilityDescription: L10n.share)
        return item
    }

    private func sharePicker() -> NSSharingServicePicker? {
        withSelectedFileSecurityScopes { urls in
            let picker = NSSharingServicePicker(items: urls)
            picker.delegate = self
            return picker
        }
    }

    private func tagsMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.tags)
        let commonLabel = selectedItemsLabelNumber()
        for label in FileTagLabel.allCases {
            let item = NSMenuItem(title: label.title, action: #selector(setSelectedItemsTag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = label.labelNumber
            item.state = commonLabel == label.labelNumber ? .on : .off
            item.image = label.image
            menu.addItem(item)
        }
        return menu
    }

    private func pasteboardFileURLs() -> [URL] {
        NSPasteboard.general.fileURLs ?? []
    }

    private func pasteMenuTitle() -> String? {
        let urls = pasteboardFileURLs()
        guard let firstURL = urls.first else { return nil }
        let baseTitle = urls.count == 1 ? firstURL.lastPathComponent : "\(firstURL.lastPathComponent)..."
        return "\(L10n.paste) \"\(truncatedMenuTitle(baseTitle, maxLength: 36))\""
    }

    private func truncatedMenuTitle(_ title: String, maxLength: Int) -> String {
        guard title.count > maxLength, maxLength > 3 else { return title }
        let headCount = (maxLength - 3) / 2
        let tailCount = maxLength - 3 - headCount
        let head = title.prefix(headCount)
        let tail = title.suffix(tailCount)
        return "\(head)...\(tail)"
    }

    private func appStoreSearchQuery() -> String? {
        guard let item = selectedItems().first, !item.isDirectory else { return nil }
        let url = item.url
        if !url.pathExtension.isEmpty {
            return url.pathExtension
        }
        if let typeIdentifier = item.typeIdentifier,
           let type = UTType(typeIdentifier) {
            if let preferredExtension = type.preferredFilenameExtension, !preferredExtension.isEmpty {
                return preferredExtension
            }
            return type.identifier
        }
        return url.lastPathComponent
    }

    private func newItemMenuImage(for kind: NewItemKind) -> NSImage? {
        if let appURL = kind.appURL {
            return AppIconProvider.menuFileImage(appURL.path, accessibilityDescription: kind.title)
                ?? AppIconProvider.menuImage(kind.symbol, accessibilityDescription: kind.title)
        }
        return AppIconProvider.menuImage(kind.symbol, accessibilityDescription: kind.title)
    }

    private func selectedFileURLs() -> [URL] {
        selectedItems().map(\.url)
    }

    private func withSelectedFileSecurityScopes<T>(_ body: ([URL]) -> T) -> T? {
        let urls = selectedFileURLs()
        guard !urls.isEmpty else { return nil }
        let scopes = startSecurityScopes(for: urls)
        defer { stopSecurityScopes(scopes) }
        return body(urls)
    }

    private func startSecurityScopes(for urls: [URL]) -> [(url: URL, didStartAccessing: Bool)] {
        var scopedPaths: Set<String> = []
        return urls.compactMap { url in
            guard let securityScopeURL = directoryAccessStore.securityScopeURL(for: url) else { return nil }
            let path = securityScopeURL.path
            guard scopedPaths.insert(path).inserted else { return nil }
            return (url: securityScopeURL, didStartAccessing: securityScopeURL.startAccessingSecurityScopedResource())
        }
    }

    private func stopSecurityScopes(_ scopes: [(url: URL, didStartAccessing: Bool)]) {
        for scope in scopes where scope.didStartAccessing {
            scope.url.stopAccessingSecurityScopedResource()
        }
    }

    private func selectedItemsLabelNumber() -> Int? {
        let labels = selectedFileURLs().map { url -> Int? in
            do {
                return try url.resourceValues(forKeys: [.labelNumberKey]).labelNumber
            } catch {
                return nil
            }
        }
        guard let first = labels.first, labels.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func airDropSharingService() -> NSSharingService? {
        NSSharingService(named: .sendViaAirDrop)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        let airDropTitle = airDropSharingService()?.menuItemTitle
        return proposedServices.filter { service in
            service.menuItemTitle != airDropTitle
        }
    }

    private func confirmPermanentDelete(count: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.deleteImmediatelyPrompt
        alert.informativeText = String.localizedStringWithFormat(L10n.deleteImmediatelyMessage, count)
        alert.addButton(withTitle: L10n.deleteImmediately)
        alert.addButton(withTitle: L10n.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showFinderInfo(for urls: [URL]) throws {
        do {
            try runAppleScript(finderInfoScript(for: urls))
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            try runAppleScript(finderInfoFallbackScript())
        }
    }

    private func finderInfoScript(for urls: [URL]) -> String {
        let aliases = urls.map { "POSIX file \"\($0.path.replacingOccurrences(of: "\"", with: "\\\""))\" as alias" }.joined(separator: ", ")
        return """
        tell application "Finder"
            activate
            repeat with targetItem in {\(aliases)}
                open information window of (targetItem as alias)
            end repeat
        end tell
        """
    }

    private func finderInfoFallbackScript() -> String {
        """
        tell application "Finder" to activate
        delay 0.1
        tell application "System Events"
            keystroke "i" using command down
        end tell
        """
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CloverError.unsupportedOperation
        }
        script.executeAndReturnError(&error)
        if let error {
            throw NSError(domain: "Clover.FinderInfo", code: 1, userInfo: error as? [String: Any])
        }
    }
}

private enum FileTagLabel: CaseIterable {
    case none
    case gray
    case green
    case purple
    case blue
    case yellow
    case red
    case orange

    var labelNumber: Int? {
        switch self {
        case .none:
            return nil
        case .gray:
            return 1
        case .green:
            return 2
        case .purple:
            return 3
        case .blue:
            return 4
        case .yellow:
            return 5
        case .red:
            return 6
        case .orange:
            return 7
        }
    }

    var title: String {
        switch self {
        case .none:
            return L10n.none
        case .gray:
            return L10n.tagGray
        case .green:
            return L10n.tagGreen
        case .purple:
            return L10n.tagPurple
        case .blue:
            return L10n.tagBlue
        case .yellow:
            return L10n.tagYellow
        case .red:
            return L10n.tagRed
        case .orange:
            return L10n.tagOrange
        }
    }

    var image: NSImage? {
        switch self {
        case .none:
            return AppIconProvider.image(.tag, accessibilityDescription: title)
        case .gray:
            return AppIconProvider.tagColorImage(.systemGray, accessibilityDescription: title)
        case .green:
            return AppIconProvider.tagColorImage(.systemGreen, accessibilityDescription: title)
        case .purple:
            return AppIconProvider.tagColorImage(.systemPurple, accessibilityDescription: title)
        case .blue:
            return AppIconProvider.tagColorImage(.systemBlue, accessibilityDescription: title)
        case .yellow:
            return AppIconProvider.tagColorImage(.systemYellow, accessibilityDescription: title)
        case .red:
            return AppIconProvider.tagColorImage(.systemRed, accessibilityDescription: title)
        case .orange:
            return AppIconProvider.tagColorImage(.systemOrange, accessibilityDescription: title)
        }
    }
}
