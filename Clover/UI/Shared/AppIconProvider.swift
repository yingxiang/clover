import AppKit

enum NewItemKind: Int, CaseIterable {
    case folder = 1
    case textFile
    case markdownFile
    case word
    case excel
    case powerPoint
    case keynote
    case pages
    case numbers
    case wps

    var title: String {
        switch self {
        case .folder:
            return L10n.newFolder
        case .textFile:
            return L10n.newTextFile
        case .markdownFile:
            return L10n.newMarkdownFile
        case .word:
            return L10n.newWordDocument
        case .excel:
            return L10n.newExcelWorkbook
        case .powerPoint:
            return L10n.newPowerPointPresentation
        case .keynote:
            return L10n.newKeynotePresentation
        case .pages:
            return L10n.newPagesDocument
        case .numbers:
            return L10n.newNumbersSpreadsheet
        case .wps:
            return L10n.newWPSDocument
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .folder:
            return .folderPlus
        case .textFile:
            return .textFile
        case .markdownFile:
            return .markdown
        case .word:
            return .word
        case .excel:
            return .excel
        case .powerPoint:
            return .powerPoint
        case .keynote:
            return .keynote
        case .pages:
            return .pages
        case .numbers:
            return .numbers
        case .wps:
            return .wps
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .folder, .textFile, .markdownFile:
            return []
        case .word:
            return ["com.microsoft.Word"]
        case .excel:
            return ["com.microsoft.Excel"]
        case .powerPoint:
            return ["com.microsoft.Powerpoint", "com.microsoft.PowerPoint"]
        case .keynote:
            return ["com.apple.iWork.Keynote"]
        case .pages:
            return ["com.apple.iWork.Pages"]
        case .numbers:
            return ["com.apple.Numbers"]
        case .wps:
            return ["com.kingsoft.wpsoffice.mac", "cn.wps.wps", "com.wps.Office"]
        }
    }

    var applicationNames: [String] {
        switch self {
        case .folder, .textFile, .markdownFile:
            return []
        case .word:
            return ["Microsoft Word", "Word"]
        case .excel:
            return ["Microsoft Excel", "Excel"]
        case .powerPoint:
            return ["Microsoft PowerPoint", "PowerPoint"]
        case .keynote:
            return ["Keynote"]
        case .pages:
            return ["Pages"]
        case .numbers:
            return ["Numbers"]
        case .wps:
            return ["WPS Office", "WPS"]
        }
    }

    var defaultName: String {
        switch self {
        case .folder:
            return L10n.untitledFolder
        case .textFile:
            return L10n.untitledTextFile
        case .markdownFile:
            return L10n.untitledMarkdownFile
        case .word:
            return "Word"
        case .excel:
            return "Excel"
        case .powerPoint:
            return "PowerPoint"
        case .keynote:
            return "Keynote"
        case .pages:
            return "Pages"
        case .numbers:
            return "Numbers"
        case .wps:
            return "WPS"
        }
    }

    var fileExtension: String? {
        switch self {
        case .textFile:
            return "txt"
        case .markdownFile:
            return "md"
        default:
            return nil
        }
    }

    var appURL: URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }
        for applicationName in applicationNames {
            if let url = Self.applicationURL(named: applicationName) {
                return url
            }
        }
        return nil
    }

    private static func applicationURL(named applicationName: String) -> URL? {
        let fileManager = FileManager.default
        let candidateDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            UserDirectories.homeURL.appendingPathComponent("Applications", isDirectory: true)
        ]

        for directory in candidateDirectories {
            let url = directory.appendingPathComponent("\(applicationName).app", isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    var isAvailable: Bool {
        switch self {
        case .folder, .textFile, .markdownFile:
            return true
        case .word, .excel, .powerPoint, .keynote, .pages, .numbers, .wps:
            return appURL != nil
        }
    }
}

enum AppSymbol: String {
    case home = "house"
    case desktop = "macwindow"
    case documents = "doc.text"
    case downloads = "arrow.down.circle"
    case applications = "app"
    case folder = "folder"
    case file = "doc"
    case search = "magnifyingglass"
    case refresh = "arrow.clockwise"
    case trash = "trash"
    case copy = "doc.on.doc"
    case move = "arrow.right"
    case rename = "pencil"
    case preview = "eye"
    case grid = "square.grid.2x2"
    case list = "list.bullet"
    case layoutSplit = "rectangle.split.2x1"
    case sidebar = "sidebar.left"
    case back = "chevron.left"
    case forward = "chevron.right"
    case share = "square.and.arrow.up"
    case airDrop = "dot.radiowaves.left.and.right"
    case info = "info.circle"
    case finder = "safari"
    case terminal = "terminal"
    case deleteImmediately = "trash.slash"
    case openWith = "arrow.up.forward.app"
    case tag = "tag"
    case paste = "doc.on.clipboard"
    case selectAll = "checklist"
    case screenshot = "camera.viewfinder"
    case support = "heart"
    case folderPlus = "folder.badge.plus"
    case open = "arrow.up.right.square"
    case textFile = "doc.plaintext"
    case markdown = "chevron.left.forwardslash.chevron.right"
    case appStore = "bag"
    case otherApp = "ellipsis.circle"
    case word = "doc.text.image"
    case excel = "tablecells"
    case powerPoint = "chart.bar.doc.horizontal"
    case keynote = "play.rectangle.on.rectangle"
    case pages = "doc.richtext"
    case numbers = "number.square"
    case wps = "wonsign.square"
}

enum AppIconProvider {
    static func image(_ symbol: AppSymbol, accessibilityDescription: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: accessibilityDescription)
    }

    static func menuImage(_ symbol: AppSymbol, accessibilityDescription: String? = nil) -> NSImage? {
        if symbol == .finder {
            return finderMenuImage(accessibilityDescription: accessibilityDescription)
        }
        return normalizedMenuImage(
            image(symbol, accessibilityDescription: accessibilityDescription),
            accessibilityDescription: accessibilityDescription
        )
    }

    static func menuApplicationImage(bundleIdentifier: String, accessibilityDescription: String? = nil) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return menuFileImage(url.path, accessibilityDescription: accessibilityDescription)
    }

    static func menuFileImage(_ path: String, accessibilityDescription: String? = nil) -> NSImage? {
        normalizedMenuImage(NSWorkspace.shared.icon(forFile: path), accessibilityDescription: accessibilityDescription)
    }

    static func menuImage(from image: NSImage?, accessibilityDescription: String? = nil) -> NSImage? {
        normalizedMenuImage(image, accessibilityDescription: accessibilityDescription)
    }

    static func tagColorImage(_ color: NSColor, accessibilityDescription: String? = nil) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func finderMenuImage(accessibilityDescription: String?) -> NSImage? {
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            return menuFileImage(finderURL.path, accessibilityDescription: accessibilityDescription)
        }
        return normalizedMenuImage(image(.finder, accessibilityDescription: accessibilityDescription), accessibilityDescription: accessibilityDescription)
    }

    private static func normalizedMenuImage(_ image: NSImage?, accessibilityDescription: String?) -> NSImage? {
        guard let image else { return nil }
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        copy.accessibilityDescription = accessibilityDescription
        return copy
    }
}
