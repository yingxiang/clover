import AppKit

final class WorkspaceViewController: NSViewController {
    private let paneController: PaneLayoutController
    private let statusBar = StatusBarView()

    init(environment: AppEnvironment) {
        paneController = PaneLayoutController(environment: environment)
        super.init(nibName: nil, bundle: nil)
        paneController.statusHandler = { [weak self] text in
            self?.statusBar.setText(text)
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

    func openInActivePane(_ url: URL) {
        paneController.openInActivePane(url)
    }
}
