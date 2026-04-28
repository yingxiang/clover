import Foundation

struct SidebarItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var path: String
    var systemIconName: String?
    var children: [SidebarItem]

    var url: URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    init(id: UUID = UUID(), title: String, url: URL, systemIconName: String?, children: [SidebarItem] = []) {
        self.id = id
        self.title = title
        self.path = url.path
        self.systemIconName = systemIconName
        self.children = children
    }
}
