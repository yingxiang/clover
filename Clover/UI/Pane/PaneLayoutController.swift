import AppKit

final class PaneLayoutController: NSViewController {
    var statusHandler: ((String) -> Void)?
    var activePaneChangeHandler: (() -> Void)?

    private let environment: AppEnvironment
    private(set) var layout: PaneLayout = .single
    private var panes: [FilePaneViewController] = []
    private weak var activePane: FilePaneViewController?

    var activePaneID: UUID? {
        activePane?.viewModel.id
    }

    var paneCount: Int {
        panes.count
    }

    var currentLayout: PaneLayout {
        layout
    }

    var currentFileViewMode: FileViewMode {
        activePane?.viewModel.viewMode ?? .list
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

    func openInActivePane(_ url: URL) {
        activePane?.open(url)
    }

    func setFileViewModeInActivePane(_ mode: FileViewMode) {
        activePane?.setViewMode(mode)
        statusHandler?(mode == .list ? "View: List" : "View: Grid")
    }

    func activatePane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        setActivePane(panes[index])
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
        statusHandler?("Layout: \(displayName(for: newLayout))")
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
        statusHandler?("Restored workspace")
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
        let pane = FilePaneViewController(viewModel: viewModel)
        pane.statusHandler = { [weak self] text in
            self?.statusHandler?(text)
        }
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
        activePaneChangeHandler?()
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

    private func displayName(for layout: PaneLayout) -> String {
        switch layout {
        case .single:
            return "Single"
        case .twoVertical:
            return "Two Vertical"
        case .twoHorizontal:
            return "Two Horizontal"
        case .fourGrid:
            return "Four Grid"
        }
    }
}
