import AppKit

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
}

enum AppIconProvider {
    static func image(_ symbol: AppSymbol, accessibilityDescription: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: accessibilityDescription)
    }
}
