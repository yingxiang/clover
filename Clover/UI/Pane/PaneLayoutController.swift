import AppKit

final class PaneLayoutController: NSViewController {
    var statusHandler: ((String) -> Void)?

    private let environment: AppEnvironment
    private var layout: PaneLayout = .single
    private var panes: [FilePaneViewController] = []
    private weak var activePane: FilePaneViewController?

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

    func openInActivePane(_ url: URL) {
        activePane?.open(url)
    }

    func setLayout(_ newLayout: PaneLayout) {
        layout = newLayout
        let count = paneCount(for: newLayout)
        while panes.count < count {
            panes.append(makePane())
        }
        if panes.count > count {
            panes = Array(panes.prefix(count))
        }
        rebuildLayout()
        if activePane == nil {
            setActivePane(panes.first)
        }
    }

    private func makePane() -> FilePaneViewController {
        let viewModel = FilePaneViewModel(provider: environment.fileProvider)
        viewModel.onStatusChange = { [weak self] text in
            self?.statusHandler?(text)
        }
        let pane = FilePaneViewController(viewModel: viewModel)
        pane.activationHandler = { [weak self] pane in
            self?.setActivePane(pane)
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
            arrangedView = split(axis: .horizontal, panes: Array(panes.prefix(2)))
        case .twoHorizontal:
            arrangedView = split(axis: .vertical, panes: Array(panes.prefix(2)))
        case .fourGrid:
            let top = split(axis: .horizontal, panes: Array(panes.prefix(2)))
            let bottom = split(axis: .horizontal, panes: Array(panes.dropFirst(2).prefix(2)))
            arrangedView = stack(axis: .vertical, views: [top, bottom])
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

    private func split(axis: NSUserInterfaceLayoutOrientation, panes: [FilePaneViewController]) -> NSView {
        panes.forEach { addChild($0) }
        return stack(axis: axis, views: panes.map(\.view))
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
    }

    private func paneCount(for layout: PaneLayout) -> Int {
        switch layout {
        case .single:
            return 1
        case .twoVertical, .twoHorizontal:
            return 2
        case .fourGrid:
            return 4
        }
    }
}
