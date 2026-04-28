import XCTest
@testable import Clover

final class FileSortServiceTests: XCTestCase {
    func testDirectoriesSortBeforeFilesByName() {
        let folder = FileItem(url: URL(fileURLWithPath: "/tmp/Folder"), name: "Folder", isDirectory: true, size: nil, modificationDate: nil, creationDate: nil, typeIdentifier: nil, isHidden: false)
        let file = FileItem(url: URL(fileURLWithPath: "/tmp/A.txt"), name: "A.txt", isDirectory: false, size: 10, modificationDate: nil, creationDate: nil, typeIdentifier: "public.text", isHidden: false)

        let sorted = FileSortService.sort([file, folder], by: .nameAscending)

        XCTAssertEqual(sorted.map(\.name), ["Folder", "A.txt"])
    }
}
