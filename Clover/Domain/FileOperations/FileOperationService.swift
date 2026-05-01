import Foundation

enum FileOperationKind: Sendable {
    case copy
    case move
    case rename
    case trash
    case deletePermanently
    case createFolder
    case createFile
}

enum FileOperationState {
    case pending
    case running
    case completed
    case failed(Error)
    case cancelled
}

enum FileConflictResolution: Sendable {
    case replace
    case skip
    case keepBoth
    case cancel
    indirect case applyToAll(FileConflictResolution)
}

struct FileConflict: Sendable {
    let kind: FileOperationKind
    let sourceURL: URL
    let destinationURL: URL
}

typealias FileConflictResolver = @MainActor (FileConflict) async -> FileConflictResolution

struct FileOperationTask: Identifiable {
    var id: UUID
    var kind: FileOperationKind
    var sourceURLs: [URL]
    var destinationURL: URL?
    var progress: Progress
    var state: FileOperationState
}

final class FileOperationService: Sendable {
    private let provider: any FileProvider

    init(provider: any FileProvider) {
        self.provider = provider
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        do {
            return try await provider.createFolder(at: parentURL, name: name)
        } catch CloverError.fileAlreadyExists {
            return try await provider.createFolder(at: parentURL, name: uniqueName(for: name, attempt: 2))
        }
    }

    func createFile(at parentURL: URL, name: String, contents: Data) async throws -> URL {
        do {
            return try await provider.createFile(at: parentURL, name: name, contents: contents)
        } catch CloverError.fileAlreadyExists {
            let extensionName = URL(fileURLWithPath: name).pathExtension
            let baseName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            return try await provider.createFile(
                at: parentURL,
                name: uniqueName(for: baseName, pathExtension: extensionName, attempt: 2),
                contents: contents
            )
        }
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        try await provider.renameItem(at: url, to: newName)
    }

    func moveItems(_ urls: [URL], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        try await perform(.move, urls: urls, destinationURL: destinationURL, conflictResolver: conflictResolver)
    }

    func copyItems(_ urls: [URL], to destinationURL: URL, conflictResolver: FileConflictResolver? = nil) async throws {
        try await perform(.copy, urls: urls, destinationURL: destinationURL, conflictResolver: conflictResolver)
    }

    func trashItems(_ urls: [URL]) async throws {
        try await provider.trashItems(urls)
    }

    func deleteItemsPermanently(_ urls: [URL]) async throws {
        try await provider.deleteItemsPermanently(urls)
    }

    func setLabelNumber(_ labelNumber: Int?, for urls: [URL]) async throws {
        try await provider.setLabelNumber(labelNumber, for: urls)
    }

    private func perform(_ kind: FileOperationKind, urls: [URL], destinationURL: URL, conflictResolver: FileConflictResolver?) async throws {
        var applyToAllResolution: FileConflictResolution?

        for url in urls {
            try Task.checkCancellation()
            var target = destinationURL.appendingPathComponent(url.lastPathComponent, isDirectory: url.hasDirectoryPath)

            while true {
                do {
                    switch kind {
                    case .copy:
                        try await provider.copyItem(at: url, to: target)
                    case .move:
                        try await provider.moveItem(at: url, to: target)
                    default:
                        throw CloverError.unsupportedOperation
                    }
                    break
                } catch CloverError.fileAlreadyExists {
                    let resolution = try await conflictResolution(
                        kind: kind,
                        sourceURL: url,
                        destinationURL: target,
                        resolver: conflictResolver,
                        applyToAllResolution: &applyToAllResolution
                    )

                    switch resolution {
                    case .replace:
                        try await provider.deleteItemsPermanently([target])
                        continue
                    case .skip:
                        break
                    case .keepBoth:
                        target = uniqueDestination(for: target)
                        continue
                    case .cancel:
                        throw CloverError.operationCancelled
                    case .applyToAll:
                        continue
                    }
                    break
                }
            }
        }
    }

    private func conflictResolution(
        kind: FileOperationKind,
        sourceURL: URL,
        destinationURL: URL,
        resolver: FileConflictResolver?,
        applyToAllResolution: inout FileConflictResolution?
    ) async throws -> FileConflictResolution {
        if let applyToAllResolution {
            return applyToAllResolution
        }

        guard let resolver else {
            throw CloverError.fileAlreadyExists(destinationURL)
        }

        let resolution = await resolver(FileConflict(kind: kind, sourceURL: sourceURL, destinationURL: destinationURL))
        if case .applyToAll(let nestedResolution) = resolution {
            applyToAllResolution = nestedResolution
            return nestedResolution
        }
        return resolution
    }

    private func uniqueDestination(for url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var attempt = 2
        while true {
            let name = uniqueName(for: base, pathExtension: pathExtension, attempt: attempt)
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: url.hasDirectoryPath)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            attempt += 1
        }
    }

    private func uniqueName(for name: String, pathExtension: String = "", attempt: Int) -> String {
        if pathExtension.isEmpty {
            return "\(name) \(attempt)"
        }
        return "\(name) \(attempt).\(pathExtension)"
    }
}
