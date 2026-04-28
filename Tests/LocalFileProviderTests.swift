import XCTest
@testable import Clover

final class LocalFileProviderTests: XCTestCase {
    func testListDirectoryReturnsCreatedFile() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("CloverProviderTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("sample.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let provider = LocalFileProvider()
        let items = try await provider.listDirectory(at: root)

        XCTAssertTrue(items.contains { $0.name == "sample.txt" && !$0.isDirectory })
    }
}
