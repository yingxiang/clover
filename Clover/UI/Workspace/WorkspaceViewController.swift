import AppKit

final class WorkspaceViewController: NSViewController {
    var activePaneChangeHandler: (() -> Void)?
    var activePanePathChangeHandler: ((URL) -> Void)?
    var commandAvailabilityChangeHandler: (() -> Void)?

    private let paneController: PaneLayoutController

    init(environment: AppEnvironment) {
        paneController = PaneLayoutController(environment: environment)
        super.init(nibName: nil, bundle: nil)
        paneController.activePaneChangeHandler = { [weak self] in
            self?.activePaneChangeHandler?()
        }
        paneController.activePanePathChangeHandler = { [weak self] url in
            self?.activePanePathChangeHandler?(url)
        }
        paneController.commandAvailabilityChangeHandler = { [weak self] in
            self?.commandAvailabilityChangeHandler?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(paneController)
        paneController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paneController.view)

        NSLayoutConstraint.activate([
            paneController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paneController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneController.view.topAnchor.constraint(equalTo: view.topAnchor),
            paneController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func refreshActivePane() {
        paneController.refreshActivePane()
    }

    func focusActivePathInput() {
        paneController.focusActivePathInput()
    }

    func createFolderInActivePane() {
        paneController.createFolderInActivePane()
    }

    func createTextFileInActivePane() {
        paneController.createTextFileInActivePane()
    }

    func performNewItemActionInActivePane(_ kind: NewItemKind) {
        paneController.performNewItemActionInActivePane(kind)
    }

    func renameSelectedItemInActivePane() {
        paneController.renameSelectedItemInActivePane()
    }

    func copySelectedItemsInActivePane() {
        paneController.copySelectedItemsInActivePane()
    }

    func moveSelectedItemsInActivePane() {
        paneController.moveSelectedItemsInActivePane()
    }

    func trashSelectedItemsInActivePane() {
        paneController.trashSelectedItemsInActivePane()
    }

    func copySelectionInActivePane() {
        paneController.copySelectionInActivePane()
    }

    func pasteIntoActivePane() {
        paneController.pasteIntoActivePane()
    }

    func selectAllInActivePane() {
        paneController.selectAllInActivePane()
    }

    func deleteSelectedItemsPermanentlyInActivePane() {
        paneController.deleteSelectedItemsPermanentlyInActivePane()
    }

    func revealSelectedItemsInFinderInActivePane() {
        paneController.revealSelectedItemsInFinderInActivePane()
    }

    func openSelectedItemsInTerminalInActivePane() {
        paneController.openSelectedItemsInTerminalInActivePane()
    }

    func copySelectedPathsInActivePane() {
        paneController.copySelectedPathsInActivePane()
    }

    func showSelectedItemsInfoInActivePane() {
        paneController.showSelectedItemsInfoInActivePane()
    }

    func sendSelectedItemsViaAirDropInActivePane() {
        paneController.sendSelectedItemsViaAirDropInActivePane()
    }

    func showShareMenuInActivePane(relativeTo view: NSView?) {
        paneController.showShareMenuInActivePane(relativeTo: view)
    }

    func canPerformFileAction(_ action: Selector) -> Bool {
        paneController.canPerformFileAction(action)
    }

    func setPaneLayout(_ layout: PaneLayout) {
        paneController.setLayout(layout)
    }

    func activateNextPane() {
        paneController.activateNextPane()
    }

    func activatePreviousPane() {
        paneController.activatePreviousPane()
    }

    func restore(from workspace: Workspace) {
        paneController.restore(from: workspace)
    }

    func workspaceState(using store: WorkspaceStore) -> (layout: PaneLayout, panes: [PaneState]) {
        paneController.workspaceState(using: store)
    }

    var currentPaneLayout: PaneLayout {
        paneController.currentLayout
    }

    var currentFileViewMode: FileViewMode {
        paneController.currentFileViewMode
    }

    var activePaneURL: URL? {
        paneController.activePaneURL
    }

    var activePaneSelectedURLs: [URL] {
        paneController.activePaneSelectedURLs
    }

    var paneURLs: [URL] {
        paneController.paneURLs
    }

    var canActivateAdjacentPane: Bool {
        paneController.canActivateAdjacentPane
    }

    func openInActivePane(_ url: URL) {
        paneController.openInActivePane(url)
    }

    func setFileViewModeInActivePane(_ mode: FileViewMode) {
        paneController.setFileViewModeInActivePane(mode)
    }
}
