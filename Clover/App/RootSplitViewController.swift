import AppKit

final class RootSplitViewController: NSSplitViewController {
    var activePaneChangeHandler: (() -> Void)?

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

    func setPaneLayout(_ layout: PaneLayout) {
        workspaceViewController.setPaneLayout(layout)
    }

    var currentPaneLayout: PaneLayout {
        workspaceViewController.currentPaneLayout
    }

    var currentFileViewMode: FileViewMode {
        workspaceViewController.currentFileViewMode
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
