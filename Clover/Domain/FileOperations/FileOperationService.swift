import Foundation

enum FileOperationKind {
    case copy
    case move
    case rename
    case trash
    case deletePermanently
    case createFolder
}

enum FileOperationState {
    case pending
    case running
    case completed
    case failed(Error)
    case cancelled
}

enum FileConflictResolution {
    case replace
    case skip
    case keepBoth
    case cancel
    indirect case applyToAll(FileConflictResolution)
}

struct FileOperationTask: Identifiable {
    var id: UUID
    var kind: FileOperationKind
    var sourceURLs: [URL]
    var destinationURL: URL?
    var progress: Progress
    var state: FileOperationState
}

final class FileOperationService {
    private let provider: any FileProvider

    init(provider: any FileProvider) {
        self.provider = provider
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        try await provider.createFolder(at: parentURL, name: name)
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        try await provider.renameItem(at: url, to: newName)
    }

    func moveItems(_ urls: [URL], to destinationURL: URL) async throws {
        try await provider.moveItems(urls, to: destinationURL)
    }

    func copyItems(_ urls: [URL], to destinationURL: URL) async throws {
        try await provider.copyItems(urls, to: destinationURL)
    }

    func trashItems(_ urls: [URL]) async throws {
        try await provider.trashItems(urls)
    }
}
