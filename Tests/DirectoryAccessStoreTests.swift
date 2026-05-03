import XCTest
@testable import Clover

final class DirectoryAccessStoreTests: XCTestCase {
    func testResolvedURLUsesAuthorizedAncestorDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let child = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)

        let store = try DirectoryAccessStore(
            storageURL: root.appendingPathComponent("bookmarks.plist", isDirectory: false)
        )
        try store.saveAccess(to: root)

        XCTAssertEqual(store.resolvedURL(for: child), child.standardizedFileURL)
    }

    func testResolvedURLDoesNotTreatSiblingPrefixAsAuthorizedAncestor() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let authorized = root.appendingPathComponent("Documents", isDirectory: true)
        let siblingWithPrefix = root.appendingPathComponent("Documents Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: authorized, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: siblingWithPrefix, withIntermediateDirectories: false)

        let store = try DirectoryAccessStore(
            storageURL: root.appendingPathComponent("bookmarks.plist", isDirectory: false)
        )
        try store.saveAccess(to: authorized)

        XCTAssertNil(store.resolvedURL(for: siblingWithPrefix))
    }

    func testHasDirectoryAccessReturnsTrueForReadableDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try DirectoryAccessStore(
            storageURL: root.appendingPathComponent("bookmarks.plist", isDirectory: false)
        )

        XCTAssertTrue(store.hasDirectoryAccess(to: root))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloverDirectoryAccessStoreTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
