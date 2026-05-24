import XCTest
@testable import Clover

final class StashShelfStoreTests: XCTestCase {
    func testSaveLoadAndClearItems() throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("stash.json", isDirectory: false)
        let store = try StashShelfStore(storageURL: storageURL)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        let item = StashItem(url: fileURL, bookmarkStore: BookmarkStore())

        _ = try store.addItems([fileURL], bookmarkStore: BookmarkStore())
        let loaded = try store.loadItems()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.path, item.path)

        try store.clear()
        XCTAssertTrue(try store.loadItems().isEmpty)
    }
}
