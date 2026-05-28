import AppKit
import Foundation
import UniformTypeIdentifiers

final class LocalFileProvider: FileProvider {
    let providerID = "local"
    let displayName = "Local Files"
    private let securityScopeURLProvider: @Sendable (URL) -> URL?
    private let openURLHandler: @MainActor @Sendable (URL) -> Bool

    init(
        securityScopeURLProvider: (@Sendable (URL) -> URL?)? = nil,
        openURLHandler: (@MainActor @Sendable (URL) -> Bool)? = nil
    ) {
        self.securityScopeURLProvider = securityScopeURLProvider ?? { _ in nil }
        self.openURLHandler = openURLHandler ?? { url in
            NSWorkspace.shared.open(url)
        }
    }

    func listDirectory(at url: URL) async throws -> [FileItem] {
        try await runScopedFileOperation(scopes: [url], errorURL: url) {
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
                .isHiddenKey,
                .labelNumberKey
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
                        isApplication: isApplication,
                        labelNumber: values.labelNumber
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
        }
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        try await runScopedFileOperation(scopes: [parentURL], errorURL: parentURL) {
            let fileManager = FileManager.default
            let url = parentURL.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }
    }

    func createFile(at parentURL: URL, name: String, contents: Data) async throws -> URL {
        try await runScopedFileOperation(scopes: [parentURL], errorURL: parentURL) {
            let fileManager = FileManager.default
            let url = parentURL.appendingPathComponent(name, isDirectory: false)
            if fileManager.fileExists(atPath: url.path) {
                throw CloverError.fileAlreadyExists(url)
            }
            try contents.write(to: url, options: .withoutOverwriting)
            return url
        }
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        let parentURL = url.deletingLastPathComponent()
        return try await runScopedFileOperation(scopes: [parentURL], errorURL: parentURL) {
            let fileManager = FileManager.default
            let destination = parentURL.appendingPathComponent(newName)
            if fileManager.fileExists(atPath: destination.path) {
                throw CloverError.fileAlreadyExists(destination)
            }
            try fileManager.moveItem(at: url, to: destination)
            return destination
        }
    }

    func moveItem(at url: URL, to destinationURL: URL) async throws {
        let sourceParentURL = url.deletingLastPathComponent()
        let destinationParentURL = destinationURL.deletingLastPathComponent()
        try await runScopedFileOperation(scopes: [sourceParentURL, destinationParentURL], errorURL: destinationParentURL) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                throw CloverError.fileAlreadyExists(destinationURL)
            }
            try fileManager.moveItem(at: url, to: destinationURL)
        }
    }

    func copyItem(at url: URL, to destinationURL: URL) async throws {
        let sourceParentURL = url.deletingLastPathComponent()
        let destinationParentURL = destinationURL.deletingLastPathComponent()
        try await runScopedFileOperation(scopes: [sourceParentURL, destinationParentURL], errorURL: destinationParentURL) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                throw CloverError.fileAlreadyExists(destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)
        }
    }

    func moveItems(_ urls: [URL], to destinationURL: URL) async throws {
        try await runScopedFileOperation(
            scopes: urls.map { $0.deletingLastPathComponent() } + [destinationURL],
            errorURL: destinationURL
        ) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    throw CloverError.fileAlreadyExists(destination)
                }
                try fileManager.moveItem(at: url, to: destination)
            }
        }
    }

    func copyItems(_ urls: [URL], to destinationURL: URL) async throws {
        try await runScopedFileOperation(
            scopes: urls.map { $0.deletingLastPathComponent() } + [destinationURL],
            errorURL: destinationURL
        ) {
            let fileManager = FileManager.default
            for url in urls {
                try Task.checkCancellation()
                let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    throw CloverError.fileAlreadyExists(destination)
                }
                try fileManager.copyItem(at: url, to: destination)
            }
        }
    }

    func trashItems(_ urls: [URL]) async throws {
        try await runScopedFileOperation(groups: groupedURLsByParent(urls)) { group in
            let fileManager = FileManager.default
            for url in group.urls {
                try Task.checkCancellation()
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            }
        }
    }

    func deleteItemsPermanently(_ urls: [URL]) async throws {
        try await runScopedFileOperation(groups: groupedURLsByParent(urls)) { group in
            let fileManager = FileManager.default
            for url in group.urls {
                try Task.checkCancellation()
                try fileManager.removeItem(at: url)
            }
        }
    }

    func setLabelNumber(_ labelNumber: Int?, for urls: [URL]) async throws {
        try await runScopedFileOperation(groups: groupedURLsByParent(urls)) { group in
            for url in group.urls {
                try Task.checkCancellation()
                var values = URLResourceValues()
                values.labelNumber = labelNumber
                var mutableURL = url
                try mutableURL.setResourceValues(values)
            }
        }
    }

    func extractArchive(at url: URL, to destinationDirectoryURL: URL) async throws -> URL {
        return try await runScopedFileOperation(scopes: [url, destinationDirectoryURL], errorURL: destinationDirectoryURL) {
            let fileManager = FileManager.default
            let destinationURL = self.uniqueExtractionDirectory(for: url, in: destinationDirectoryURL, fileManager: fileManager)
            do {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
                try self.extractArchive(sourceURL: url, destinationURL: destinationURL)
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw self.normalized(error, for: destinationDirectoryURL)
            }
            return destinationURL
        }
    }

    func createArchive(from urls: [URL], in destinationDirectoryURL: URL, suggestedName: String) async throws -> URL {
        return try await runScopedFileOperation(scopes: urls.map { $0.deletingLastPathComponent() } + [destinationDirectoryURL], errorURL: destinationDirectoryURL) {
            let fileManager = FileManager.default
            let archiveURL = self.uniqueArchiveURL(named: suggestedName, in: destinationDirectoryURL, fileManager: fileManager)
            let archiveBaseDirectoryURL = self.commonArchiveBaseDirectory(for: urls) ?? destinationDirectoryURL
            let relativePaths = urls.map { self.archiveRelativePath(for: $0, relativeTo: archiveBaseDirectoryURL) }
            do {
                try self.runArchiveTool(
                    executablePath: "/usr/bin/zip",
                    arguments: ["-qry", archiveURL.path] + relativePaths,
                    failurePrefix: "zip",
                    currentDirectoryURL: archiveBaseDirectoryURL
                )
            } catch {
                try? fileManager.removeItem(at: archiveURL)
                throw self.normalized(error, for: destinationDirectoryURL)
            }
            return archiveURL
        }
    }

    func openItem(_ url: URL) async throws {
        let didOpen = try await runScopedFileOperation(scopes: [url], errorURL: url) {
            await MainActor.run {
                self.openURLHandler(url)
            }
        }
        if !didOpen {
            throw CloverError.unsupportedOperation
        }
    }

    private func displayName(for url: URL, fallbackName: String, isApplication: Bool) -> String {
        guard isApplication else { return fallbackName }
        let displayName = FileManager.default.displayName(atPath: url.path)
        return displayName.isEmpty ? fallbackName : displayName
    }

    private func securityScopeURL(for url: URL) -> URL {
        securityScopeURLProvider(url.standardizedFileURL) ?? url
    }

    private func runScopedFileOperation<T: Sendable>(
        scopes: [URL],
        errorURL: URL,
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let scopeURLs = uniqueScopeURLs(for: scopes)
        return try await Task.detached(priority: priority) {
            let accesses = scopeURLs.map(SecurityScopedAccess.init)
            defer {
                for access in accesses.reversed() {
                    access.stop()
                }
            }

            do {
                return try await operation()
            } catch {
                throw self.normalized(error, for: errorURL)
            }
        }.value
    }

    private func runScopedFileOperation(
        groups: [ScopedURLGroup],
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable (ScopedURLGroup) throws -> Void
    ) async throws {
        try await Task.detached(priority: priority) {
            for group in groups {
                let scopedAccess = SecurityScopedAccess(group.accessURL)
                defer { scopedAccess.stop() }

                do {
                    try operation(group)
                } catch {
                    throw self.normalized(error, for: group.parentURL)
                }
            }
        }.value
    }

    private func uniqueScopeURLs(for urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        var scopeURLs: [URL] = []
        for url in urls {
            let scopeURL = securityScopeURL(for: url)
            let path = scopeURL.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { continue }
            scopeURLs.append(scopeURL)
        }
        return scopeURLs
    }

    private func groupedURLsByParent(_ urls: [URL]) -> [ScopedURLGroup] {
        var groups: [String: ScopedURLGroup] = [:]
        for url in urls {
            let parentURL = url.deletingLastPathComponent().standardizedFileURL
            let key = parentURL.path
            if var group = groups[key] {
                group.urls.append(url)
                groups[key] = group
            } else {
                groups[key] = ScopedURLGroup(
                    parentURL: parentURL,
                    accessURL: securityScopeURL(for: parentURL),
                    urls: [url]
                )
            }
        }
        return groups.values.sorted { $0.parentURL.path < $1.parentURL.path }
    }

    private func uniqueExtractionDirectory(for archiveURL: URL, in parentURL: URL, fileManager: FileManager) -> URL {
        let baseName = archiveURL.deletingPathExtension().lastPathComponent.isEmpty
            ? "Archive"
            : archiveURL.deletingPathExtension().lastPathComponent
        var candidate = parentURL.appendingPathComponent(baseName, isDirectory: true)
        var attempt = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName) \(attempt)", isDirectory: true)
            attempt += 1
        }
        return candidate
    }

    private func uniqueArchiveURL(named suggestedName: String, in parentURL: URL, fileManager: FileManager) -> URL {
        let suggestedURL = URL(fileURLWithPath: suggestedName)
        let extensionName = suggestedURL.pathExtension.isEmpty ? "zip" : suggestedURL.pathExtension
        let baseName = suggestedURL.deletingPathExtension().lastPathComponent.isEmpty
            ? "Archive"
            : suggestedURL.deletingPathExtension().lastPathComponent
        var candidate = parentURL.appendingPathComponent("\(baseName).\(extensionName)", isDirectory: false)
        var attempt = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName) \(attempt).\(extensionName)", isDirectory: false)
            attempt += 1
        }
        return candidate
    }

    private func commonArchiveBaseDirectory(for urls: [URL]) -> URL? {
        let parentPaths = urls
            .map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
            .filter { !$0.isEmpty }
        guard var commonComponents = parentPaths.first else { return nil }

        for components in parentPaths.dropFirst() {
            commonComponents = Array(zip(commonComponents, components).prefix { $0 == $1 }.map(\.0))
            if commonComponents.isEmpty { return nil }
        }

        let path = NSString.path(withComponents: commonComponents)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func archiveRelativePath(for url: URL, relativeTo parentURL: URL) -> String {
        let parentPath = parentURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = parentPath.hasSuffix("/") ? parentPath : "\(parentPath)/"
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }

    private func extractArchive(sourceURL: URL, destinationURL: URL) throws {
        if shouldExtractWithTar(sourceURL) {
            try runArchiveTool(
                executablePath: "/usr/bin/tar",
                arguments: ["-xf", sourceURL.path, "-C", destinationURL.path],
                failurePrefix: "tar"
            )
        } else {
            try runArchiveTool(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", sourceURL.path, destinationURL.path],
                failurePrefix: "ditto"
            )
        }
    }

    private func shouldExtractWithTar(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        let tarSuffixes = [
            ".tar",
            ".tgz",
            ".tar.gz",
            ".tbz",
            ".tbz2",
            ".tar.bz2",
            ".txz",
            ".tar.xz"
        ]
        return tarSuffixes.contains { filename.hasSuffix($0) }
    }

    private func runArchiveTool(executablePath: String, arguments: [String], failurePrefix: String, currentDirectoryURL: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveExtractionError(message: message?.isEmpty == false ? message! : "\(failurePrefix) exited with status \(process.terminationStatus)")
        }
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

private struct ArchiveExtractionError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct ScopedURLGroup: Sendable {
    let parentURL: URL
    let accessURL: URL
    var urls: [URL]
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
