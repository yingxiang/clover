import XCTest
@testable import Clover

final class LocalFileProviderTests: XCTestCase {
    func testListDirectoryReturnsFileMetadata() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("sample.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let provider = LocalFileProvider()
        let items = try await provider.listDirectory(at: root)
        let item = try XCTUnwrap(items.first { $0.name == "sample.txt" })

        XCTAssertEqual(item.url.resolvingSymlinksInPath(), fileURL.resolvingSymlinksInPath())
        XCTAssertFalse(item.isDirectory)
        XCTAssertEqual(item.size, 5)
        XCTAssertNotNil(item.modificationDate)
        XCTAssertNotNil(item.creationDate)
        XCTAssertNotNil(item.typeIdentifier)
        XCTAssertFalse(item.isHidden)
    }

    func testListDirectoryReturnsDirectoryAndHiddenFileMetadata() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let folderURL = root.appendingPathComponent("Folder", isDirectory: true)
        let hiddenURL = root.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try Data().write(to: hiddenURL)

        let provider = LocalFileProvider()
        let items = try await provider.listDirectory(at: root)
        let folder = try XCTUnwrap(items.first { $0.name == "Folder" })
        let hidden = try XCTUnwrap(items.first { $0.name == ".hidden" })

        XCTAssertTrue(folder.isDirectory)
        XCTAssertNil(folder.size)
        XCTAssertTrue(hidden.isHidden)
    }

    func testListDirectoryTreatsAppPackagesAsOpenableFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appURL = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: false)
        try Data(repeating: 1, count: 12).write(to: appURL.appendingPathComponent("payload"))

        let provider = LocalFileProvider()
        let items = try await provider.listDirectory(at: root)
        let app = try XCTUnwrap(items.first { $0.url.standardizedFileURL == appURL.standardizedFileURL })

        XCTAssertTrue(app.isDirectory)
        XCTAssertTrue(app.isPackage)
        XCTAssertTrue(app.isApplication)
        XCTAssertFalse(app.isBrowsableDirectory)
        XCTAssertNil(app.size)
    }

    func testListDirectoryThrowsForMissingDirectory() async throws {
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Missing-\(UUID().uuidString)", isDirectory: true)
        let provider = LocalFileProvider()

        do {
            _ = try await provider.listDirectory(at: missingURL)
            XCTFail("Expected directoryNotFound error.")
        } catch let CloverError.directoryNotFound(url) {
            XCTAssertEqual(url, missingURL)
        } catch {
            XCTFail("Expected directoryNotFound, got \(error).")
        }
    }

    func testListDirectoryThrowsForFileURL() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("sample.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let provider = LocalFileProvider()

        do {
            _ = try await provider.listDirectory(at: fileURL)
            XCTFail("Expected directoryNotFound error.")
        } catch let CloverError.directoryNotFound(url) {
            XCTAssertEqual(url, fileURL)
        } catch {
            XCTFail("Expected directoryNotFound, got \(error).")
        }
    }

    func testListDirectoryResolvesSecurityScopeForRequestedDirectory() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let child = root.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        try "hello".write(to: child.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)

        let requestedURLs = LockedURLs()
        let provider = LocalFileProvider { url in
            requestedURLs.append(url)
            return root
        }

        let items = try await provider.listDirectory(at: child)

        XCTAssertTrue(items.contains { $0.name == "sample.txt" })
        XCTAssertEqual(requestedURLs.values, [child.standardizedFileURL])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CloverProviderTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [URL] = []

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ url: URL) {
        lock.lock()
        storedValues.append(url)
        lock.unlock()
    }
}
