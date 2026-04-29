import AppKit
import Foundation

final class LocalFileProvider: FileProvider {
    let providerID = "local"
    let displayName = "Local Files"

    init() {}

    func listDirectory(at url: URL) async throws -> [FileItem] {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CloverError.directoryNotFound(url)
            }

            let keys: Set<URLResourceKey> = [
                .nameKey,
                .isDirectoryKey,
                .fileSizeKey,
                .totalFileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .contentTypeKey,
                .isHiddenKey
            ]
            let childURLs = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants])

            return childURLs.compactMap { childURL in
                do {
                    let values = try childURL.resourceValues(forKeys: keys)
                    let name = values.name ?? childURL.lastPathComponent
                    let isDirectory = values.isDirectory ?? false
                    return FileItem(
                        url: childURL,
                        name: name,
                        isDirectory: isDirectory,
                        size: isDirectory ? nil : Int64(values.totalFileSize ?? values.fileSize ?? 0),
                        modificationDate: values.contentModificationDate,
                        creationDate: values.creationDate,
                        typeIdentifier: values.contentType?.identifier,
                        isHidden: values.isHidden ?? name.hasPrefix(".")
                    )
                } catch {
                    let name = childURL.lastPathComponent
                    var isDirectory: ObjCBool = false
                    _ = fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
                    return FileItem(
                        url: childURL,
                        name: name,
                        isDirectory: isDirectory.boolValue,
                        size: nil,
                        modificationDate: nil,
                        creationDate: nil,
                        typeIdentifier: nil,
                        isHidden: name.hasPrefix(".")
                    )
                }
            }
        }.value
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let url = parentURL.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }.value
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
            if fileManager.fileExists(atPath: destination.path) {
                throw CloverError.fileAlreadyExists(destination)
            }
            try fileManager.moveItem(at: url, to: destination)
            return destination
        }.value
    }

    func moveItems(_ urls: [URL], to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    throw CloverError.fileAlreadyExists(destination)
                }
                try fileManager.moveItem(at: url, to: destination)
            }
        }.value
    }

    func copyItems(_ urls: [URL], to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    throw CloverError.fileAlreadyExists(destination)
                }
                try fileManager.copyItem(at: url, to: destination)
            }
        }.value
    }

    func trashItems(_ urls: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            }
        }.value
    }

    func deleteItemsPermanently(_ urls: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                try fileManager.removeItem(at: url)
            }
        }.value
    }

    func openItem(_ url: URL) async throws {
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}
