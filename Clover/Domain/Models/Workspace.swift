import Foundation

struct Workspace: Codable, Identifiable {
    var id: UUID
    var name: String
    var layout: PaneLayout
    var panes: [PaneState]
    var windowFrame: String
    var sidebarWidth: Double
    var isSidebarCollapsed: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        layout: PaneLayout,
        panes: [PaneState],
        windowFrame: String,
        sidebarWidth: Double,
        isSidebarCollapsed: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.layout = layout
        self.panes = panes
        self.windowFrame = windowFrame
        self.sidebarWidth = sidebarWidth
        self.isSidebarCollapsed = isSidebarCollapsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case layout
        case panes
        case windowFrame
        case sidebarWidth
        case isSidebarCollapsed
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        layout = try container.decode(PaneLayout.self, forKey: .layout)
        panes = try container.decode([PaneState].self, forKey: .panes)
        windowFrame = try container.decode(String.self, forKey: .windowFrame)
        sidebarWidth = try container.decode(Double.self, forKey: .sidebarWidth)
        isSidebarCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isSidebarCollapsed) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
