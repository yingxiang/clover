import AppKit
import Foundation
import UniformTypeIdentifiers

final class LocalFileProvider: FileProvider {
    let providerID = "local"
    let displayName = "Local Files"

    init() {}

    func listDirectory(at url: URL) async throws -> [FileItem] {
        try await Task.detached(priority: .userInitiated) {
            let scopedAccess = SecurityScopedAccess(url)
            defer { scopedAccess.stop() }
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CloverError.directoryNotFound(url)
            }

            let keys: Set<URLResourceKey> = [
                .nameKey,
                .isDirectoryKey,
                .isPackageKey,
                .fileSizeKey,
                .totalFileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey,
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
                    let isPackage = values.isPackage ?? false
                    let isApplication = values.contentType?.conforms(to: .application) == true
                    let size: Int64? = if isDirectory {
                        nil
                    } else {
                        Int64(values.totalFileSize ?? values.fileSize ?? 0)
                    }
                    return FileItem(
                        url: childURL,
                        name: name,
                        isDirectory: isDirectory,
                        size: size,
                        modificationDate: values.contentModificationDate,
                        creationDate: values.creationDate,
                        typeIdentifier: values.contentType?.identifier,
                        isHidden: values.isHidden ?? name.hasPrefix("."),
                        isPackage: isPackage,
                        isApplication: isApplication
                    )
                } catch {
                    let name = childURL.lastPathComponent
                    var isDirectory: ObjCBool = false
                    _ = fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
                    let isApplication = childURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame
                    return FileItem(
                        url: childURL,
                        name: name,
                        isDirectory: isDirectory.boolValue,
                        size: nil,
                        modificationDate: nil,
                        creationDate: nil,
                        typeIdentifier: nil,
                        isHidden: name.hasPrefix("."),
                        isPackage: isApplication,
                        isApplication: isApplication
                    )
                }
            }
        }.value
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let scopedAccess = SecurityScopedAccess(parentURL)
            defer { scopedAccess.stop() }
            let fileManager = FileManager.default
            let url = parentURL.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }.value
    }

    func createFile(at parentURL: URL, name: String, contents: Data) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let scopedAccess = SecurityScopedAccess(parentURL)
            defer { scopedAccess.stop() }
            let fileManager = FileManager.default
            let url = parentURL.appendingPathComponent(name, isDirectory: false)
            if fileManager.fileExists(atPath: url.path) {
                throw CloverError.fileAlreadyExists(url)
            }
            try contents.write(to: url, options: .withoutOverwriting)
            return url
        }.value
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let scopedAccess = SecurityScopedAccess(url.deletingLastPathComponent())
            defer { scopedAccess.stop() }
            let fileManager = FileManager.default
            let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
            if fileManager.fileExists(atPath: destination.path) {
                throw CloverError.fileAlreadyExists(destination)
            }
            try fileManager.moveItem(at: url, to: destination)
            return destination
        }.value
    }

    func moveItem(at url: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let sourceAccess = SecurityScopedAccess(url.deletingLastPathComponent())
            let destinationAccess = SecurityScopedAccess(destinationURL.deletingLastPathComponent())
            defer {
                destinationAccess.stop()
                sourceAccess.stop()
            }
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                throw CloverError.fileAlreadyExists(destinationURL)
            }
            try fileManager.moveItem(at: url, to: destinationURL)
        }.value
    }

    func copyItem(at url: URL, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let sourceAccess = SecurityScopedAccess(url.deletingLastPathComponent())
            let destinationAccess = SecurityScopedAccess(destinationURL.deletingLastPathComponent())
            defer {
                destinationAccess.stop()
                sourceAccess.stop()
            }
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                throw CloverError.fileAlreadyExists(destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
        }.value
    }

    func moveItems(_ urls: [URL], to destinationURL: URL) async throws {
        for url in urls {
            try Task.checkCancellation()
            let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
            try await moveItem(at: url, to: destination)
        }
    }

    func copyItems(_ urls: [URL], to destinationURL: URL) async throws {
        for url in urls {
            try Task.checkCancellation()
            let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
            try await copyItem(at: url, to: destination)
        }
    }

    func trashItems(_ urls: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                let scopedAccess = SecurityScopedAccess(url.deletingLastPathComponent())
                defer { scopedAccess.stop() }
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
                let scopedAccess = SecurityScopedAccess(url.deletingLastPathComponent())
                defer { scopedAccess.stop() }
                try fileManager.removeItem(at: url)
            }
        }.value
    }

    func setLabelNumber(_ labelNumber: Int?, for urls: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            for url in urls {
                try Task.checkCancellation()
                let scopedAccess = SecurityScopedAccess(url.deletingLastPathComponent())
                defer { scopedAccess.stop() }
                var values = URLResourceValues()
                values.labelNumber = labelNumber
                var mutableURL = url
                try mutableURL.setResourceValues(values)
            }
        }.value
    }

    func openItem(_ url: URL) async throws {
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

private final class SecurityScopedAccess: @unchecked Sendable {
    private let url: URL
    private let didStartAccessing: Bool

    init(_ url: URL) {
        self.url = url
        didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    func stop() {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
