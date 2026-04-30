import AppKit

final class WorkspaceViewController: NSViewController {
    var activePaneChangeHandler: (() -> Void)?

    private let paneController: PaneLayoutController
    private let statusBar = StatusBarView()

    init(environment: AppEnvironment) {
        paneController = PaneLayoutController(environment: environment)
        super.init(nibName: nil, bundle: nil)
        paneController.statusHandler = { [weak self] text in
            self?.statusBar.setText(text)
        }
        paneController.activePaneChangeHandler = { [weak self] in
            self?.activePaneChangeHandler?()
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
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paneController.view)
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            paneController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paneController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneController.view.topAnchor.constraint(equalTo: view.topAnchor),
            paneController.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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

    func setPaneLayout(_ layout: PaneLayout) {
        paneController.setLayout(layout)
    }

    var currentPaneLayout: PaneLayout {
        paneController.currentLayout
    }

    var currentFileViewMode: FileViewMode {
        paneController.currentFileViewMode
    }

    func openInActivePane(_ url: URL) {
        paneController.openInActivePane(url)
    }

    func setFileViewModeInActivePane(_ mode: FileViewMode) {
        paneController.setFileViewModeInActivePane(mode)
    }
}
