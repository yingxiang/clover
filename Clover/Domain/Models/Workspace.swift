import Foundation

struct Workspace: Codable, Identifiable {
    var id: UUID
    var name: String
    var layout: PaneLayout
    var panes: [PaneState]
    var windowFrame: String
    var sidebarWidth: Double
    var createdAt: Date
    var updatedAt: Date
}
