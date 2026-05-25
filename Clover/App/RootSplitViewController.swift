import AppKit

final class RootSplitViewController: NSSplitViewController {
    var activePaneChangeHandler: (() -> Void)?
    var activePanePathChangeHandler: ((URL) -> Void)?
    var commandAvailabilityChangeHandler: (() -> Void)?

    private let environment: AppEnvironment
    private let sidebarViewController: SidebarViewController
    private let workspaceViewController: WorkspaceViewController
    private weak var sidebarSplitViewItem: NSSplitViewItem?
    private var lastExpandedSidebarWidth: CGFloat = 220

    init(environment: AppEnvironment) {
        self.environment = environment
        sidebarViewController = SidebarViewController(entitlementService: environment.entitlementService)
        workspaceViewController = WorkspaceViewController(environment: environment)
        super.init(nibName: nil, bundle: nil)
        sidebarViewController.delegate = self
        workspaceViewController.activePaneChangeHandler = { [weak self] in
            self?.activePaneChangeHandler?()
        }
        workspaceViewController.activePanePathChangeHandler = { [weak self] url in
            self?.activePanePathChangeHandler?(url)
        }
        workspaceViewController.commandAvailabilityChangeHandler = { [weak self] in
            self?.commandAvailabilityChangeHandler?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        sidebarSplitViewItem = sidebarItem

        let workspaceItem = NSSplitViewItem(viewController: workspaceViewController)
        workspaceItem.minimumThickness = 520

        addSplitViewItem(sidebarItem)
        addSplitViewItem(workspaceItem)
    }

    func refreshActivePane() {
        workspaceViewController.refreshActivePane()
    }

    func focusActivePathInput() {
        workspaceViewController.focusActivePathInput()
    }

    func createFolderInActivePane() {
        workspaceViewController.createFolderInActivePane()
    }

    func createTextFileInActivePane() {
        workspaceViewController.createTextFileInActivePane()
    }

    func performNewItemActionInActivePane(_ kind: NewItemKind) {
        workspaceViewController.performNewItemActionInActivePane(kind)
    }

    func renameSelectedItemInActivePane() {
        workspaceViewController.renameSelectedItemInActivePane()
    }

    func copySelectedItemsInActivePane() {
        workspaceViewController.copySelectedItemsInActivePane()
    }

    func moveSelectedItemsInActivePane() {
        workspaceViewController.moveSelectedItemsInActivePane()
    }

    func trashSelectedItemsInActivePane() {
        workspaceViewController.trashSelectedItemsInActivePane()
    }

    func copySelectionInActivePane() {
        workspaceViewController.copySelectionInActivePane()
    }

    func pasteIntoActivePane() {
        workspaceViewController.pasteIntoActivePane()
    }

    func selectAllInActivePane() {
        workspaceViewController.selectAllInActivePane()
    }

    func deleteSelectedItemsPermanentlyInActivePane() {
        workspaceViewController.deleteSelectedItemsPermanentlyInActivePane()
    }

    func revealSelectedItemsInFinderInActivePane() {
        workspaceViewController.revealSelectedItemsInFinderInActivePane()
    }

    func openSelectedItemsInTerminalInActivePane() {
        workspaceViewController.openSelectedItemsInTerminalInActivePane()
    }

    func copySelectedPathsInActivePane() {
        workspaceViewController.copySelectedPathsInActivePane()
    }

    func showSelectedItemsInfoInActivePane() {
        workspaceViewController.showSelectedItemsInfoInActivePane()
    }

    func sendSelectedItemsViaAirDropInActivePane() {
        workspaceViewController.sendSelectedItemsViaAirDropInActivePane()
    }

    func showShareMenuInActivePane(relativeTo view: NSView?) {
        workspaceViewController.showShareMenuInActivePane(relativeTo: view)
    }

    func canPerformFileAction(_ action: Selector) -> Bool {
        workspaceViewController.canPerformFileAction(action)
    }

    func setPaneLayout(_ layout: PaneLayout) {
        workspaceViewController.setPaneLayout(layout)
    }

    func activateNextPane() {
        workspaceViewController.activateNextPane()
    }

    func activatePreviousPane() {
        workspaceViewController.activatePreviousPane()
    }

    func restore(from workspace: Workspace) {
        workspaceViewController.restore(from: workspace)
        lastExpandedSidebarWidth = max(CGFloat(workspace.sidebarWidth), 180)
        splitView.layoutSubtreeIfNeeded()
        if workspace.isSidebarCollapsed {
            setSidebarCollapsed(true)
        } else {
            setSidebarCollapsed(false)
            splitView.setPosition(lastExpandedSidebarWidth, ofDividerAt: 0)
        }
    }

    func workspaceSnapshot(name: String, windowFrame: String, using store: WorkspaceStore) -> Workspace {
        let state = workspaceViewController.workspaceState(using: store)
        let sidebarWidth = isSidebarCollapsed ? lastExpandedSidebarWidth : (splitViewItems.first?.viewController.view.frame.width ?? lastExpandedSidebarWidth)
        return Workspace(
            id: UUID(),
            name: name,
            layout: state.layout,
            panes: state.panes,
            windowFrame: windowFrame,
            sidebarWidth: sidebarWidth,
            isSidebarCollapsed: isSidebarCollapsed,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    var currentPaneLayout: PaneLayout {
        workspaceViewController.currentPaneLayout
    }

    var currentFileViewMode: FileViewMode {
        workspaceViewController.currentFileViewMode
    }

    var activePaneURL: URL? {
        workspaceViewController.activePaneURL
    }

    var canActivateAdjacentPane: Bool {
        workspaceViewController.canActivateAdjacentPane
    }

    func setFileViewModeInActivePane(_ mode: FileViewMode) {
        workspaceViewController.setFileViewModeInActivePane(mode)
    }

    func openInActivePane(_ url: URL) {
        workspaceViewController.openInActivePane(url)
    }

    func activePaneSelectedURLs() -> [URL] {
        workspaceViewController.activePaneSelectedURLs
    }

    func paneURLs() -> [URL] {
        workspaceViewController.paneURLs
    }

    func restoreWorkspace(_ workspace: Workspace) {
        workspaceViewController.restore(from: workspace)
        activePaneChangeHandler?()
        activePanePathChangeHandler?(workspace.panes.first.flatMap { environment.workspaceStore.resolvedURL(for: $0) } ?? UserDirectories.homeURL)
    }

    var isSidebarCollapsed: Bool {
        sidebarSplitViewItem?.isCollapsed ?? false
    }

    func toggleSidebar() {
        setSidebarCollapsed(!isSidebarCollapsed, animated: true)
    }

    private func setSidebarCollapsed(_ collapsed: Bool, animated: Bool = false) {
        guard let sidebarSplitViewItem else { return }
        if !collapsed {
            let currentWidth = sidebarSplitViewItem.viewController.view.frame.width
            if currentWidth >= sidebarSplitViewItem.minimumThickness {
                lastExpandedSidebarWidth = currentWidth
            }
        } else if !sidebarSplitViewItem.isCollapsed {
            lastExpandedSidebarWidth = max(sidebarSplitViewItem.viewController.view.frame.width, sidebarSplitViewItem.minimumThickness)
        }

        let item = animated ? sidebarSplitViewItem.animator() : sidebarSplitViewItem
        item.isCollapsed = collapsed
        if !collapsed {
            let restoreWidth = lastExpandedSidebarWidth
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    self.splitView.animator().setPosition(restoreWidth, ofDividerAt: 0)
                }
            } else {
                splitView.layoutSubtreeIfNeeded()
                splitView.setPosition(restoreWidth, ofDividerAt: 0)
            }
        }
    }
}

extension RootSplitViewController: SidebarViewControllerDelegate {
    func sidebarViewController(_ controller: SidebarViewController, didSelect url: URL) {
        workspaceViewController.openInActivePane(url)
    }
}
