import AppKit

final class RootSplitViewController: NSSplitViewController {
    var activePaneChangeHandler: (() -> Void)?
    var activePanePathChangeHandler: ((URL) -> Void)?
    var commandAvailabilityChangeHandler: (() -> Void)?

    private let sidebarViewController: SidebarViewController
    private let workspaceViewController: WorkspaceViewController

    init(environment: AppEnvironment) {
        sidebarViewController = SidebarViewController()
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

        let sidebarItem = NSSplitViewItem(viewController: sidebarViewController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = false

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

    func restore(from workspace: Workspace) {
        workspaceViewController.restore(from: workspace)
        if workspace.sidebarWidth > 0 {
            splitView.layoutSubtreeIfNeeded()
            splitView.setPosition(workspace.sidebarWidth, ofDividerAt: 0)
        }
    }

    func workspaceSnapshot(name: String, windowFrame: String, using store: WorkspaceStore) -> Workspace {
        let state = workspaceViewController.workspaceState(using: store)
        let sidebarWidth = splitViewItems.first?.viewController.view.frame.width ?? 220
        return Workspace(
            id: UUID(),
            name: name,
            layout: state.layout,
            panes: state.panes,
            windowFrame: windowFrame,
            sidebarWidth: sidebarWidth,
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

    func setFileViewModeInActivePane(_ mode: FileViewMode) {
        workspaceViewController.setFileViewModeInActivePane(mode)
    }
}

extension RootSplitViewController: SidebarViewControllerDelegate {
    func sidebarViewController(_ controller: SidebarViewController, didSelect url: URL) {
        workspaceViewController.openInActivePane(url)
    }
}
