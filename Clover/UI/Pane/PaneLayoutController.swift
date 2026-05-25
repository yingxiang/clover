import AppKit

final class PaneLayoutController: NSViewController {
    var statusHandler: ((String) -> Void)?
    var activePaneChangeHandler: (() -> Void)?
    var activePanePathChangeHandler: ((URL) -> Void)?
    var commandAvailabilityChangeHandler: (() -> Void)?

    private let environment: AppEnvironment
    private(set) var layout: PaneLayout = .single
    private var panes: [FilePaneViewController] = []
    private weak var activePane: FilePaneViewController?
    private var paneSelectionOverlays: [Int: PaneSelectionOverlayView] = [:]

    var activePaneID: UUID? {
        activePane?.viewModel.id
    }

    var paneCount: Int {
        panes.count
    }

    var canActivateAdjacentPane: Bool {
        panes.count > 1
    }

    var currentLayout: PaneLayout {
        layout
    }

    var currentFileViewMode: FileViewMode {
        activePane?.viewModel.viewMode ?? .list
    }

    var activePaneURL: URL? {
        activePane?.viewModel.currentURL
    }

    var activePaneSelectedURLs: [URL] {
        activePane?.selectedItems().map(\.url) ?? []
    }

    var paneURLs: [URL] {
        panes.map { $0.viewModel.currentURL }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setLayout(.single)
    }

    func refreshActivePane() {
        activePane?.refresh()
    }

    func focusActivePathInput() {
        activePane?.focusPathInput(nil)
    }

    func createFolderInActivePane() {
        activePane?.createFolder(nil)
    }

    func createTextFileInActivePane() {
        activePane?.createTextFile(nil)
    }

    func performNewItemActionInActivePane(_ kind: NewItemKind) {
        let item = NSMenuItem()
        item.tag = kind.rawValue
        activePane?.performNewItemAction(item)
    }

    func renameSelectedItemInActivePane() {
        activePane?.renameSelectedItem(nil)
    }

    func copySelectedItemsInActivePane() {
        activePane?.copySelectedItems(nil)
    }

    func moveSelectedItemsInActivePane() {
        activePane?.moveSelectedItems(nil)
    }

    func trashSelectedItemsInActivePane() {
        activePane?.trashSelectedItems(nil)
    }

    func copySelectionInActivePane() {
        activePane?.copySelectionToPasteboard(nil)
    }

    func pasteIntoActivePane() {
        activePane?.pasteFromPasteboard(nil)
    }

    func selectAllInActivePane() {
        activePane?.selectAllItems(nil)
    }

    func deleteSelectedItemsPermanentlyInActivePane() {
        activePane?.deleteSelectedItemsPermanently(nil)
    }

    func revealSelectedItemsInFinderInActivePane() {
        activePane?.revealSelectedItemsInFinder(nil)
    }

    func openSelectedItemsInTerminalInActivePane() {
        activePane?.openSelectedItemsInTerminal(nil)
    }

    func copySelectedPathsInActivePane() {
        activePane?.copySelectedItemPaths(nil)
    }

    func showSelectedItemsInfoInActivePane() {
        activePane?.showSelectedItemsInfo(nil)
    }

    func sendSelectedItemsViaAirDropInActivePane() {
        activePane?.sendSelectedItemsViaAirDrop(nil)
    }

    func showShareMenuInActivePane(relativeTo view: NSView?) {
        activePane?.showShareMenu(relativeTo: view)
    }

    func canPerformFileAction(_ action: Selector) -> Bool {
        activePane?.canPerformFileAction(action) ?? false
    }

    func openInActivePane(_ url: URL) {
        activePane?.open(url)
    }

    func setFileViewModeInActivePane(_ mode: FileViewMode) {
        activePane?.setViewMode(mode)
        statusHandler?(L10n.viewStatus(mode == .list ? L10n.viewModeList : L10n.viewModeGrid))
    }

    func restoreWorkspace(_ workspace: Workspace) {
        restore(from: workspace)
    }

    func activatePane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        setActivePane(panes[index])
        panes[index].focusBrowser()
    }

    func activateNextPane() {
        activatePane(offset: 1)
    }

    func activatePreviousPane() {
        activatePane(offset: -1)
    }

    func setLayout(_ newLayout: PaneLayout) {
        let previousActivePane = activePane
        layout = newLayout
        let count = paneCount(for: newLayout)

        if panes.count > count, let previousActivePane, let activeIndex = panes.firstIndex(where: { $0 === previousActivePane }), activeIndex >= count {
            panes.remove(at: activeIndex)
            panes.insert(previousActivePane, at: 0)
        }

        while panes.count < count {
            panes.append(makePane())
        }
        if panes.count > count {
            panes = Array(panes.prefix(count))
        }
        rebuildLayout()
        if let previousActivePane, panes.contains(where: { $0 === previousActivePane }) {
            setActivePane(previousActivePane)
        } else {
            setActivePane(panes.first)
        }
        statusHandler?(L10n.layoutStatus(displayName(for: newLayout)))
    }

    func restore(from workspace: Workspace) {
        layout = workspace.layout
        let count = paneCount(for: workspace.layout)
        panes = workspace.panes.prefix(count).map { makePane(from: $0) }
        while panes.count < count {
            panes.append(makePane())
        }
        rebuildLayout()
        setActivePane(panes.first)
        statusHandler?(L10n.restoredWorkspace)
    }

    func workspaceState(using store: WorkspaceStore) -> (layout: PaneLayout, panes: [PaneState]) {
        (layout, panes.map { $0.viewModel.workspaceState(using: store) })
    }

    private func makePane() -> FilePaneViewController {
        let viewModel = FilePaneViewModel(provider: environment.fileProvider, fileOperationService: environment.fileOperationService)
        return makePane(viewModel: viewModel)
    }

    private func makePane(from paneState: PaneState) -> FilePaneViewController {
        let viewModel = FilePaneViewModel(
            id: paneState.id,
            currentURL: environment.workspaceStore.resolvedURL(for: paneState),
            provider: environment.fileProvider,
            fileOperationService: environment.fileOperationService
        )
        viewModel.restoreState(
            currentURL: environment.workspaceStore.resolvedURL(for: paneState),
            viewMode: paneState.viewMode,
            sortOption: paneState.sortOption
        )
        return makePane(viewModel: viewModel)
    }

    private func makePane(viewModel: FilePaneViewModel) -> FilePaneViewController {
        let pane = FilePaneViewController(viewModel: viewModel, directoryAccessStore: environment.directoryAccessStore)
        pane.statusHandler = { [weak self] text in
            self?.statusHandler?(text)
        }
        pane.activationHandler = { [weak self] pane in
            self?.setActivePane(pane)
        }
        pane.pathChangeHandler = { [weak self] pane in
            guard self?.activePane === pane else { return }
            self?.activePanePathChangeHandler?(pane.viewModel.currentURL)
        }
        pane.commandAvailabilityHandler = { [weak self] pane in
            guard self?.activePane === pane else { return }
            self?.commandAvailabilityChangeHandler?()
        }
        pane.openDirectoryInNewWindowHandler = { url in
            (NSApp.delegate as? AppDelegate)?.openDirectoryInNewWindow(url)
        }
        pane.paneOpenTargetsProvider = { [weak self] pane in
            self?.paneOpenTargets(excluding: pane) ?? []
        }
        pane.paneSelectionOverlayHandler = { [weak self] show, pane, highlightedPaneIndex in
            if show {
                self?.showPaneSelectionOverlays(excluding: pane, highlightedPaneIndex: highlightedPaneIndex)
            } else {
                self?.hidePaneSelectionOverlays()
            }
        }
        pane.openDirectoryInPaneHandler = { [weak self] paneIndex, url in
            self?.open(url, inPaneAt: paneIndex)
        }
        return pane
    }

    private func rebuildLayout() {
        children.forEach { child in
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        view.subviews.forEach { $0.removeFromSuperview() }

        let arrangedView: NSView
        switch layout {
        case .single:
            addChild(panes[0])
            arrangedView = panes[0].view
        case .twoVertical:
            Array(panes.prefix(2)).forEach { addChild($0) }
            arrangedView = split(axis: .vertical, views: Array(panes.prefix(2)).map(\.view))
        case .twoHorizontal:
            Array(panes.prefix(2)).forEach { addChild($0) }
            arrangedView = split(axis: .horizontal, views: Array(panes.prefix(2)).map(\.view))
        case .leftOneRightTwo, .leftTwoRightOne, .topOneBottomTwo, .topTwoBottomOne:
            Array(panes.prefix(3)).forEach { addChild($0) }
            arrangedView = asymmetricSplit(layout: layout, panes: Array(panes.prefix(3)))
        case .fourGrid:
            arrangedView = crossSplit(panes: Array(panes.prefix(4)))
        }

        arrangedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arrangedView)
        NSLayoutConstraint.activate([
            arrangedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arrangedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arrangedView.topAnchor.constraint(equalTo: view.topAnchor),
            arrangedView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        panes.forEach { $0.setActive($0 === activePane) }
    }

    private func split(axis: NSUserInterfaceLayoutOrientation, views: [NSView]) -> NSView {
        let splitView = BoundedPaneSplitView()
        splitView.isVertical = axis == .vertical
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        splitView.setContentHuggingPriority(.defaultLow, for: .vertical)
        splitView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        splitView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        views.forEach { paneView in
            paneView.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview(paneView)
        }
        return splitView
    }

    private func asymmetricSplit(layout: PaneLayout, panes: [FilePaneViewController]) -> NSView {
        switch layout {
        case .leftOneRightTwo:
            let right = split(axis: .horizontal, views: [panes[1].view, panes[2].view])
            return split(axis: .vertical, views: [panes[0].view, right])
        case .leftTwoRightOne:
            let left = split(axis: .horizontal, views: [panes[0].view, panes[1].view])
            return split(axis: .vertical, views: [left, panes[2].view])
        case .topOneBottomTwo:
            let bottom = split(axis: .vertical, views: [panes[1].view, panes[2].view])
            return split(axis: .horizontal, views: [panes[0].view, bottom])
        case .topTwoBottomOne:
            let top = split(axis: .vertical, views: [panes[0].view, panes[1].view])
            return split(axis: .horizontal, views: [top, panes[2].view])
        default:
            return panes.first?.view ?? NSView()
        }
    }

    private func crossSplit(panes: [FilePaneViewController]) -> NSView {
        panes.forEach { addChild($0) }
        let splitView = CrossPaneSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        splitView.setContentHuggingPriority(.defaultLow, for: .vertical)
        splitView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        splitView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        splitView.setPaneViews(panes.map(\.view))
        return splitView
    }

    private func stack(axis: NSUserInterfaceLayoutOrientation, views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = axis
        stack.distribution = .fillEqually
        stack.spacing = 1
        return stack
    }

    private func setActivePane(_ pane: FilePaneViewController?) {
        activePane = pane
        panes.forEach { $0.setActive($0 === pane) }
        activePaneChangeHandler?()
        commandAvailabilityChangeHandler?()
        if let url = pane?.viewModel.currentURL {
            activePanePathChangeHandler?(url)
        }
    }

    private func activatePane(offset: Int) {
        guard panes.count > 1 else { return }
        let currentIndex = activePane.flatMap { activePane in
            panes.firstIndex { $0 === activePane }
        } ?? 0
        let nextIndex = (currentIndex + offset + panes.count) % panes.count
        activatePane(at: nextIndex)
    }

    private func paneCount(for layout: PaneLayout) -> Int {
        switch layout {
        case .single:
            return 1
        case .twoVertical, .twoHorizontal:
            return 2
        case .leftOneRightTwo, .leftTwoRightOne, .topOneBottomTwo, .topTwoBottomOne:
            return 3
        case .fourGrid:
            return 4
        }
    }

    private func displayName(for layout: PaneLayout) -> String {
        layout.shortStatusName
    }

    private func paneOpenTargets(excluding sourcePane: FilePaneViewController) -> [(paneIndex: Int, displayNumber: Int)] {
        var displayNumber = 1
        return panes.enumerated().compactMap { index, pane in
            guard pane !== sourcePane else { return nil }
            defer { displayNumber += 1 }
            return (index, displayNumber)
        }
    }

    private func open(_ url: URL, inPaneAt paneIndex: Int) {
        guard panes.indices.contains(paneIndex) else { return }
        let targetPane = panes[paneIndex]
        targetPane.open(url)
        setActivePane(targetPane)
        targetPane.focusBrowser()
        hidePaneSelectionOverlays()
    }

    private func showPaneSelectionOverlays(excluding sourcePane: FilePaneViewController, highlightedPaneIndex: Int?) {
        let targets = paneOpenTargets(excluding: sourcePane)
        if paneSelectionOverlays.isEmpty {
            for target in targets {
                let overlay = PaneSelectionOverlayView(number: target.displayNumber)
                overlay.translatesAutoresizingMaskIntoConstraints = false
                let paneView = panes[target.paneIndex].view
                paneView.addSubview(overlay)
                NSLayoutConstraint.activate([
                    overlay.leadingAnchor.constraint(equalTo: paneView.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: paneView.trailingAnchor),
                    overlay.topAnchor.constraint(equalTo: paneView.topAnchor),
                    overlay.bottomAnchor.constraint(equalTo: paneView.bottomAnchor)
                ])
                paneSelectionOverlays[target.paneIndex] = overlay
            }
        }
        paneSelectionOverlays.forEach { paneIndex, overlay in
            overlay.setHighlighted(paneIndex == highlightedPaneIndex)
        }
    }

    private func hidePaneSelectionOverlays() {
        paneSelectionOverlays.values.forEach { $0.removeFromSuperview() }
        paneSelectionOverlays.removeAll()
    }
}

private final class PaneSelectionOverlayView: NSView {
    private let glassView = PaneSelectionOverlayView.makeGlassView()
    private let label = NSTextField(labelWithString: "")

    init(number: Int) {
        super.init(frame: .zero)
        addSubview(glassView)

        label.stringValue = "\(number)"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .textColor
        label.font = .boldSystemFont(ofSize: 48)
        addSubview(label)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.font = .boldSystemFont(ofSize: max(24, min(bounds.width, bounds.height) / 2))
    }

    func setHighlighted(_ highlighted: Bool) {
        label.textColor = highlighted ? .controlAccentColor : .textColor
    }

    private static func makeGlassView() -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.style = .regular
            return view
        }
        let view = NSVisualEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
}

private final class BoundedPaneSplitView: NSSplitView, NSSplitViewDelegate {
    private var didSetInitialDividerPosition = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    override func layout() {
        super.layout()
        setInitialDividerPositionIfNeeded()
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let availableLength = (isVertical ? bounds.width : bounds.height) - dividerThickness
        guard availableLength > 0 else { return proposedPosition }

        let minimumPaneLength = availableLength / 3
        let maximumFirstPaneLength = availableLength - minimumPaneLength
        return min(max(proposedPosition, minimumPaneLength), maximumFirstPaneLength)
    }

    private func setInitialDividerPositionIfNeeded() {
        guard !didSetInitialDividerPosition, arrangedSubviews.count >= 2 else { return }
        let availableLength = (isVertical ? bounds.width : bounds.height) - dividerThickness
        guard availableLength > 0 else { return }

        didSetInitialDividerPosition = true
        setPosition(floor(availableLength / 2), ofDividerAt: 0)
    }
}

private final class CrossPaneSplitView: NSView {
    private enum DragAxis {
        case vertical
        case horizontal
        case both
    }

    private let dividerThickness: CGFloat = 1
    private let dividerHitSlop: CGFloat = 5
    private let minimumRatio: CGFloat = 1 / 3
    private let maximumRatio: CGFloat = 2 / 3
    private var verticalRatio: CGFloat = 0.5
    private var horizontalRatio: CGFloat = 0.5
    private var paneViews: [NSView] = []
    private var dragAxis: DragAxis?

    func setPaneViews(_ views: [NSView]) {
        paneViews.forEach { $0.removeFromSuperview() }
        paneViews = Array(views.prefix(4))
        let initialFrame = bounds.isEmpty ? NSRect(x: 0, y: 0, width: 320, height: 240) : bounds
        paneViews.forEach { paneView in
            paneView.translatesAutoresizingMaskIntoConstraints = true
            paneView.autoresizingMask = []
            paneView.frame = initialFrame
            addSubview(paneView)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard paneViews.count == 4 else { return }

        let availableWidth = max(bounds.width - dividerThickness, 0)
        let availableHeight = max(bounds.height - dividerThickness, 0)
        let leftWidth = floor(availableWidth * verticalRatio)
        let rightWidth = availableWidth - leftWidth
        let topHeight = floor(availableHeight * horizontalRatio)
        let bottomHeight = availableHeight - topHeight
        let rightX = bounds.minX + leftWidth + dividerThickness
        let topY = bounds.minY + bottomHeight + dividerThickness

        paneViews[0].frame = NSRect(x: bounds.minX, y: topY, width: leftWidth, height: topHeight)
        paneViews[1].frame = NSRect(x: rightX, y: topY, width: rightWidth, height: topHeight)
        paneViews[2].frame = NSRect(x: bounds.minX, y: bounds.minY, width: leftWidth, height: bottomHeight)
        paneViews[3].frame = NSRect(x: rightX, y: bounds.minY, width: rightWidth, height: bottomHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        verticalDividerRect().fill()
        horizontalDividerRect().fill()
    }

    override func resetCursorRects() {
        addCursorRect(verticalDividerHitRect(), cursor: .resizeLeftRight)
        addCursorRect(horizontalDividerHitRect(), cursor: .resizeUpDown)
        addCursorRect(centerHitRect(), cursor: .crosshair)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        if dragAxis(at: point) != nil {
            return self
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event else { return false }
        let location = convert(event.locationInWindow, from: nil)
        return dragAxis(at: location) != nil
    }

    override func mouseDown(with event: NSEvent) {
        dragAxis = dragAxis(at: convert(event.locationInWindow, from: nil))
        if dragAxis == nil {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragAxis else { return }
        let location = convert(event.locationInWindow, from: nil)
        updateRatios(from: location, dragAxis: dragAxis)
    }

    override func mouseUp(with event: NSEvent) {
        dragAxis = nil
    }

    private func dragAxis(at location: NSPoint) -> DragAxis? {
        if centerHitRect().contains(location) {
            return .both
        }
        if verticalDividerHitRect().contains(location) {
            return .vertical
        }
        if horizontalDividerHitRect().contains(location) {
            return .horizontal
        }
        return nil
    }

    private func updateRatios(from location: NSPoint, dragAxis: DragAxis) {
        if dragAxis == .vertical || dragAxis == .both {
            let availableWidth = max(bounds.width - dividerThickness, 1)
            verticalRatio = clampedRatio((location.x - bounds.minX) / availableWidth)
        }
        if dragAxis == .horizontal || dragAxis == .both {
            let availableHeight = max(bounds.height - dividerThickness, 1)
            horizontalRatio = clampedRatio((bounds.maxY - location.y) / availableHeight)
        }
        needsLayout = true
        needsDisplay = true
    }

    private func clampedRatio(_ ratio: CGFloat) -> CGFloat {
        min(max(ratio, minimumRatio), maximumRatio)
    }

    private func verticalDividerRect() -> NSRect {
        let availableWidth = max(bounds.width - dividerThickness, 0)
        let x = bounds.minX + floor(availableWidth * verticalRatio)
        return NSRect(x: x, y: bounds.minY, width: dividerThickness, height: bounds.height)
    }

    private func horizontalDividerRect() -> NSRect {
        let availableHeight = max(bounds.height - dividerThickness, 0)
        let bottomHeight = availableHeight - floor(availableHeight * horizontalRatio)
        let y = bounds.minY + bottomHeight
        return NSRect(x: bounds.minX, y: y, width: bounds.width, height: dividerThickness)
    }

    private func verticalDividerHitRect() -> NSRect {
        verticalDividerRect().insetBy(dx: -dividerHitSlop, dy: 0)
    }

    private func horizontalDividerHitRect() -> NSRect {
        horizontalDividerRect().insetBy(dx: 0, dy: -dividerHitSlop)
    }

    private func centerHitRect() -> NSRect {
        verticalDividerRect().intersection(horizontalDividerRect()).insetBy(dx: -dividerHitSlop, dy: -dividerHitSlop)
    }
}
