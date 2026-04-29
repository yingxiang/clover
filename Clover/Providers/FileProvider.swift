import Foundation

protocol FileProvider: AnyObject, Sendable {
    var providerID: String { get }
    var displayName: String { get }

    func listDirectory(at url: URL) async throws -> [FileItem]
    func createFolder(at parentURL: URL, name: String) async throws -> URL
    func renameItem(at url: URL, to newName: String) async throws -> URL
    func moveItem(at url: URL, to destinationURL: URL) async throws
    func copyItem(at url: URL, to destinationURL: URL) async throws
    func moveItems(_ urls: [URL], to destinationURL: URL) async throws
    func copyItems(_ urls: [URL], to destinationURL: URL) async throws
    func trashItems(_ urls: [URL]) async throws
    func deleteItemsPermanently(_ urls: [URL]) async throws
    func openItem(_ url: URL) async throws
}
