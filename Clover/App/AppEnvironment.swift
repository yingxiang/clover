import Foundation
import OSLog

struct AppEnvironment {
    let fileProvider: any FileProvider
    let fileOperationService: FileOperationService
    let workspaceStore: WorkspaceStore

    static func live() -> AppEnvironment {
        let provider = LocalFileProvider()
        let workspaceStore: WorkspaceStore
        do {
            workspaceStore = try WorkspaceStore()
        } catch {
            Logger.workspace.error("Failed to initialize workspace store: \(error.localizedDescription, privacy: .public)")
            workspaceStore = try! WorkspaceStore(workspaceURL: FileManager.default.temporaryDirectory.appendingPathComponent("Clover-default-workspace.json"))
        }
        return AppEnvironment(
            fileProvider: provider,
            fileOperationService: FileOperationService(provider: provider),
            workspaceStore: workspaceStore
        )
    }
}
