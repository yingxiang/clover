import Foundation
import OSLog

struct AppEnvironment {
    let fileProvider: any FileProvider
    let fileOperationService: FileOperationService
    let workspaceStore: WorkspaceStore
    let directoryAccessStore: DirectoryAccessStore

    static func live() -> AppEnvironment {
        let provider = LocalFileProvider()
        let workspaceStore: WorkspaceStore
        let directoryAccessStore: DirectoryAccessStore
        do {
            workspaceStore = try WorkspaceStore()
        } catch {
            Logger.workspace.error("Failed to initialize workspace store: \(error.localizedDescription, privacy: .public)")
            workspaceStore = try! WorkspaceStore(workspaceURL: FileManager.default.temporaryDirectory.appendingPathComponent("Clover-default-workspace.json"))
        }
        do {
            directoryAccessStore = try DirectoryAccessStore()
        } catch {
            Logger.workspace.error("Failed to initialize directory access store: \(error.localizedDescription, privacy: .public)")
            directoryAccessStore = try! DirectoryAccessStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("Clover-directory-bookmarks.plist"))
        }
        return AppEnvironment(
            fileProvider: provider,
            fileOperationService: FileOperationService(provider: provider),
            workspaceStore: workspaceStore,
            directoryAccessStore: directoryAccessStore
        )
    }
}
