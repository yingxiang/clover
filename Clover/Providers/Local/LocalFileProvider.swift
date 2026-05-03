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
            let childURLs: [URL]
            do {
                childURLs = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants])
            } catch {
                throw self.normalized(error, for: url)
            }

            return childURLs.compactMap { childURL in
                do {
                    let values = try childURL.resourceValues(forKeys: keys)
                    let isDirectory = values.isDirectory ?? false
                    let isPackage = values.isPackage ?? false
                    let isApplication = values.contentType?.conforms(to: .application) == true
                    let name = self.displayName(for: childURL, fallbackName: values.name ?? childURL.lastPathComponent, isApplication: isApplication)
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
                    var isDirectory: ObjCBool = false
                    _ = fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory)
                    let isApplication = childURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame
                    let name = self.displayName(for: childURL, fallbackName: childURL.lastPathComponent, isApplication: isApplication)
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
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            } catch {
                throw self.normalized(error, for: parentURL)
            }
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
            do {
                try contents.write(to: url, options: .withoutOverwriting)
            } catch {
                throw self.normalized(error, for: parentURL)
            }
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
            do {
                try fileManager.moveItem(at: url, to: destination)
            } catch {
                throw self.normalized(error, for: url.deletingLastPathComponent())
            }
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
            do {
                try fileManager.moveItem(at: url, to: destinationURL)
            } catch {
                throw self.normalized(error, for: destinationURL.deletingLastPathComponent())
            }
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
            do {
                try fileManager.copyItem(at: url, to: destinationURL)
            } catch {
                throw self.normalized(error, for: destinationURL.deletingLastPathComponent())
            }
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
                do {
                    try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                } catch {
                    throw self.normalized(error, for: url.deletingLastPathComponent())
                }
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
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    throw self.normalized(error, for: url.deletingLastPathComponent())
                }
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
                do {
                    try mutableURL.setResourceValues(values)
                } catch {
                    throw self.normalized(error, for: url.deletingLastPathComponent())
                }
            }
        }.value
    }

    func openItem(_ url: URL) async throws {
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    private func displayName(for url: URL, fallbackName: String, isApplication: Bool) -> String {
        guard isApplication else { return fallbackName }
        let displayName = FileManager.default.displayName(atPath: url.path)
        return displayName.isEmpty ? fallbackName : displayName
    }

    private func normalized(_ error: Error, for url: URL) -> Error {
        if let cloverError = error as? CloverError {
            return cloverError
        }

        let nsError = error as NSError
        if isPermissionError(nsError) {
            return CloverError.permissionDenied(url)
        }
        return error
    }

    private func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            let cocoaCode = CocoaError.Code(rawValue: error.code)
            if cocoaCode == .fileReadNoPermission || cocoaCode == .fileWriteNoPermission {
                return true
            }
        }

        if error.domain == NSPOSIXErrorDomain {
            let posixCode = POSIXErrorCode(rawValue: Int32(error.code))
            if posixCode == .EPERM || posixCode == .EACCES {
                return true
            }
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlyingError)
        }

        return false
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
