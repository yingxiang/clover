import AppKit

extension PaneLayout {
    var displayName: String {
        switch self {
        case .single:
            return L10n.singlePane
        case .twoVertical:
            return L10n.twoPanesVertical
        case .twoHorizontal:
            return L10n.twoPanesHorizontal
        case .leftOneRightTwo:
            return L10n.leftOneRightTwoPane
        case .leftTwoRightOne:
            return L10n.leftTwoRightOnePane
        case .topOneBottomTwo:
            return L10n.topOneBottomTwoPane
        case .topTwoBottomOne:
            return L10n.topTwoBottomOnePane
        case .fourGrid:
            return L10n.fourPanes
        }
    }

    var shortStatusName: String {
        switch self {
        case .single:
            return L10n.single
        case .twoVertical:
            return L10n.twoVertical
        case .twoHorizontal:
            return L10n.twoHorizontal
        case .leftOneRightTwo:
            return L10n.leftOneRightTwoPane
        case .leftTwoRightOne:
            return L10n.leftTwoRightOnePane
        case .topOneBottomTwo:
            return L10n.topOneBottomTwoPane
        case .topTwoBottomOne:
            return L10n.topTwoBottomOnePane
        case .fourGrid:
            return L10n.fourGrid
        }
    }

    var toolbarImage: NSImage {
        LayoutIconFactory.image(for: self, highlighted: false)
    }

    var isProOnly: Bool {
        switch self {
        case .leftOneRightTwo, .leftTwoRightOne, .topOneBottomTwo, .topTwoBottomOne:
            return true
        case .single, .twoVertical, .twoHorizontal, .fourGrid:
            return false
        }
    }

    var menuTag: Int {
        switch self {
        case .single:
            return 1
        case .twoVertical:
            return 2
        case .twoHorizontal:
            return 3
        case .leftOneRightTwo:
            return 4
        case .leftTwoRightOne:
            return 5
        case .topOneBottomTwo:
            return 6
        case .topTwoBottomOne:
            return 7
        case .fourGrid:
            return 8
        }
    }

    init?(menuTag: Int) {
        switch menuTag {
        case 1:
            self = .single
        case 2:
            self = .twoVertical
        case 3:
            self = .twoHorizontal
        case 4:
            self = .leftOneRightTwo
        case 5:
            self = .leftTwoRightOne
        case 6:
            self = .topOneBottomTwo
        case 7:
            self = .topTwoBottomOne
        case 8:
            self = .fourGrid
        default:
            return nil
        }
    }
}

final class LayoutPickerViewController: NSViewController {
    var selectionHandler: ((PaneLayout) -> Void)?

    private let selectedLayout: PaneLayout

    init(selectedLayout: PaneLayout) {
        self.selectedLayout = selectedLayout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 12

        let grid = NSGridView(views: [
            [makeButton(.single), makeButton(.twoVertical), makeButton(.twoHorizontal), makeButton(.fourGrid)],
            [makeButton(.leftOneRightTwo), makeButton(.leftTwoRightOne), makeButton(.topOneBottomTwo), makeButton(.topTwoBottomOne)]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        rootView.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -14)
        ])

        view = rootView
    }

    private func makeButton(_ layout: PaneLayout) -> NSButton {
        let button = NSButton(image: LayoutIconFactory.image(for: layout, highlighted: layout == selectedLayout), target: self, action: #selector(selectLayout(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.tag = layout.menuTag
        button.toolTip = layout.displayName
        button.setAccessibilityLabel(layout.displayName)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    @objc private func selectLayout(_ sender: NSButton) {
        guard let layout = PaneLayout(menuTag: sender.tag) else { return }
        selectionHandler?(layout)
    }
}

enum LayoutIconFactory {
    static func image(for layout: PaneLayout, highlighted: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let strokeColor = highlighted ? NSColor.systemGreen : NSColor.secondaryLabelColor
        strokeColor.setStroke()

        let lineWidth: CGFloat = highlighted ? 2 : 1.6
        let outer = NSRect(x: 3, y: 3, width: 16, height: 16)
        let path = NSBezierPath(rect: outer)
        path.lineWidth = lineWidth
        path.stroke()

        for divider in dividers(for: layout, in: outer) {
            let dividerPath = NSBezierPath()
            dividerPath.lineWidth = lineWidth
            dividerPath.move(to: divider.start)
            dividerPath.line(to: divider.end)
            dividerPath.stroke()
        }

        return image
    }

    private static func dividers(for layout: PaneLayout, in rect: NSRect) -> [(start: NSPoint, end: NSPoint)] {
        let midX = rect.midX
        let midY = rect.midY
        switch layout {
        case .single:
            return []
        case .twoVertical:
            return [(NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: rect.maxY))]
        case .twoHorizontal:
            return [(NSPoint(x: rect.minX, y: midY), NSPoint(x: rect.maxX, y: midY))]
        case .leftOneRightTwo:
            return [
                (NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: rect.maxY)),
                (NSPoint(x: midX, y: midY), NSPoint(x: rect.maxX, y: midY))
            ]
        case .leftTwoRightOne:
            return [
                (NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: rect.maxY)),
                (NSPoint(x: rect.minX, y: midY), NSPoint(x: midX, y: midY))
            ]
        case .topOneBottomTwo:
            return [
                (NSPoint(x: rect.minX, y: midY), NSPoint(x: rect.maxX, y: midY)),
                (NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: midY))
            ]
        case .topTwoBottomOne:
            return [
                (NSPoint(x: rect.minX, y: midY), NSPoint(x: rect.maxX, y: midY)),
                (NSPoint(x: midX, y: midY), NSPoint(x: midX, y: rect.maxY))
            ]
        case .fourGrid:
            return [
                (NSPoint(x: midX, y: rect.minY), NSPoint(x: midX, y: rect.maxY)),
                (NSPoint(x: rect.minX, y: midY), NSPoint(x: rect.maxX, y: midY))
            ]
        }
    }
}
