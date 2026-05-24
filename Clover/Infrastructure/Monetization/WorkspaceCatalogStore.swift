import Foundation

final class WorkspaceCatalogStore {
    private let workspaceStore: WorkspaceStore

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    func loadWorkspaces() throws -> [Workspace] {
        try workspaceStore.loadSavedWorkspaces()
    }

    func saveCurrentWorkspace(_ workspace: Workspace, named name: String) throws -> Workspace {
        try workspaceStore.saveWorkspace(workspace, named: name)
    }

    func renameWorkspace(id: UUID, to name: String) throws -> Workspace? {
        try workspaceStore.renameWorkspace(id: id, to: name)
    }

    func deleteWorkspace(id: UUID) throws {
        try workspaceStore.deleteWorkspace(id: id)
    }
}
