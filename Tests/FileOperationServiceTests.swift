import XCTest
@testable import Clover

@MainActor
final class FileOperationServiceTests: XCTestCase {
    func testCopyConflictCanKeepBoth() async throws {
        let provider = OperationMockProvider(existingURLs: [
            URL(fileURLWithPath: "/tmp/Destination/File.txt")
        ])
        let service = FileOperationService(provider: provider)
        let source = URL(fileURLWithPath: "/tmp/Source/File.txt")
        let destination = URL(fileURLWithPath: "/tmp/Destination", isDirectory: true)

        try await service.copyItems([source], to: destination) { _ in .keepBoth }

        XCTAssertEqual(provider.copiedPairs, [
            OperationPair(source: source, destination: URL(fileURLWithPath: "/tmp/Destination/File 2.txt"))
        ])
    }

    func testCopyConflictCanReplace() async throws {
        let destinationFile = URL(fileURLWithPath: "/tmp/Destination/File.txt")
        let provider = OperationMockProvider(existingURLs: [destinationFile])
        let service = FileOperationService(provider: provider)
        let source = URL(fileURLWithPath: "/tmp/Source/File.txt")
        let destination = URL(fileURLWithPath: "/tmp/Destination", isDirectory: true)

        try await service.copyItems([source], to: destination) { _ in .replace }

        XCTAssertEqual(provider.deletedURLs, [destinationFile])
        XCTAssertEqual(provider.copiedPairs, [
            OperationPair(source: source, destination: destinationFile)
        ])
    }

    func testCopyConflictCanCancel() async throws {
        let provider = OperationMockProvider(existingURLs: [
            URL(fileURLWithPath: "/tmp/Destination/File.txt")
        ])
        let service = FileOperationService(provider: provider)
        let source = URL(fileURLWithPath: "/tmp/Source/File.txt")
        let destination = URL(fileURLWithPath: "/tmp/Destination", isDirectory: true)

        do {
            try await service.copyItems([source], to: destination) { _ in .cancel }
            XCTFail("Expected cancellation")
        } catch CloverError.operationCancelled {
            XCTAssertTrue(provider.copiedPairs.isEmpty)
        }
    }
}

private struct OperationPair: Equatable {
    let source: URL
    let destination: URL
}

private final class OperationMockProvider: FileProvider, @unchecked Sendable {
    let providerID = "operation-mock"
    let displayName = "Operation Mock"

    private let lock = NSLock()
    private var existingURLs: Set<URL>
    private var storedCopiedPairs: [OperationPair] = []
    private var storedDeletedURLs: [URL] = []

    var copiedPairs: [OperationPair] {
        lock.withLock { storedCopiedPairs }
    }

    var deletedURLs: [URL] {
        lock.withLock { storedDeletedURLs }
    }

    init(existingURLs: Set<URL>) {
        self.existingURLs = existingURLs
    }

    func listDirectory(at url: URL) async throws -> [FileItem] {
        []
    }

    func createFolder(at parentURL: URL, name: String) async throws -> URL {
        parentURL.appendingPathComponent(name, isDirectory: true)
    }

    func createFile(at parentURL: URL, name: String, contents: Data) async throws -> URL {
        parentURL.appendingPathComponent(name, isDirectory: false)
    }

    func renameItem(at url: URL, to newName: String) async throws -> URL {
        url.deletingLastPathComponent().appendingPathComponent(newName)
    }

    func moveItem(at url: URL, to destinationURL: URL) async throws {
        try recordOperation(source: url, destination: destinationURL, isCopy: false)
    }

    func copyItem(at url: URL, to destinationURL: URL) async throws {
        try recordOperation(source: url, destination: destinationURL, isCopy: true)
    }

    func moveItems(_ urls: [URL], to destinationURL: URL) async throws {
        for url in urls {
            try await moveItem(at: url, to: destinationURL.appendingPathComponent(url.lastPathComponent))
        }
    }

    func copyItems(_ urls: [URL], to destinationURL: URL) async throws {
        for url in urls {
            try await copyItem(at: url, to: destinationURL.appendingPathComponent(url.lastPathComponent))
        }
    }

    func trashItems(_ urls: [URL]) async throws {}

    func deleteItemsPermanently(_ urls: [URL]) async throws {
        lock.withLock {
            storedDeletedURLs.append(contentsOf: urls)
            urls.forEach { existingURLs.remove($0) }
        }
    }

    func setLabelNumber(_ labelNumber: Int?, for urls: [URL]) async throws {}

    func openItem(_ url: URL) async throws {}

    private func recordOperation(source: URL, destination: URL, isCopy: Bool) throws {
        try lock.withLock {
            if existingURLs.contains(destination) {
                throw CloverError.fileAlreadyExists(destination)
            }
            existingURLs.insert(destination)
            if isCopy {
                storedCopiedPairs.append(OperationPair(source: source, destination: destination))
            }
        }
    }
}
